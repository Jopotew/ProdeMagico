defmodule Prode.Matches.ExcelImporter do
  @moduledoc """
  Parses docs/matches.xlsx (or any uploaded .xlsx) and syncs teams + matches to the DB.

  Expected sheet: "Partidos"
  Required column headers (case-insensitive, order doesn't matter):
    MatchID, Grupo, Fecha, Local, Visitante, GolesLocal, GolesVisitante

  Optional columns: Hora (time in Argentina timezone, ART = UTC-3).
  When present, Fecha + Hora are combined. When absent, Fecha must include the time.

  MatchID format: "A1" … "L6"  (group letter + match number within group)
  All times are Argentina (ART = UTC-3). Stored as UTC in the database.
  """

  require Logger

  import Ecto.Query, warn: false

  alias Prode.{Repo, Tournaments}
  alias Prode.Matches.Match
  alias Prode.Tournaments.{Stage, Team}

  # --- Public API ---

  @doc "Import from a file path. Returns `{:ok, summary}` or `{:error, reason}`."
  def import_from_file(path) do
    with {:ok, package} <- XlsxReader.open(path),
         {:ok, rows} <- XlsxReader.sheet(package, "Partidos", empty_rows: false) do
      import_rows(rows)
    end
  end

  @doc "Import from binary content (for LiveView upload). Returns `{:ok, summary}` or `{:error, reason}`."
  def import_from_binary(content) do
    with {:ok, package} <- XlsxReader.open({:memory, content}),
         {:ok, rows} <- XlsxReader.sheet(package, "Partidos", empty_rows: false) do
      import_rows(rows)
    end
  end

  # --- Private ---

  defp import_rows([header_row | data_rows]) do
    cols = parse_headers(header_row)
    tournament = Tournaments.get_active_tournament!()
    stages_map = load_stages_map(tournament.id)

    results =
      data_rows
      |> Enum.reject(&empty_row?/1)
      |> Enum.map(&sync_row(&1, cols, tournament, stages_map))

    # Start/refresh MatchLockers for upcoming matches so prediction locking works
    Prode.Matches.list_upcoming_matches()
    |> Enum.each(&Prode.Predictions.MatchLockerSupervisor.start_locker/1)

    # Single broadcast so all LiveViews know to reload fixture data
    Phoenix.PubSub.broadcast(
      Prode.PubSub,
      "tournament:#{tournament.id}:fixtures_updated",
      :fixtures_updated
    )

    ok = Enum.count(results, &match?({:ok, _}, &1))
    skipped = Enum.count(results, &match?(:skip, &1))
    errors = Enum.count(results, &match?({:error, _}, &1))

    {:ok, %{synced: ok, skipped: skipped, errors: errors, total: length(results)}}
  end

  defp import_rows([]) do
    {:error, :empty_sheet}
  end

  # Maps header name (downcased, trimmed) → column index.
  defp parse_headers(header_row) do
    header_row
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn {cell, idx}, acc ->
      key = cell |> to_string() |> String.downcase() |> String.trim()
      Map.put(acc, key, idx)
    end)
  end

  defp load_stages_map(tournament_id) do
    Repo.all(from s in Stage, where: s.tournament_id == ^tournament_id)
    |> Map.new(fn s -> {s.slug, s.id} end)
  end

  defp empty_row?(row) do
    Enum.all?(row, fn cell -> is_nil(cell) or cell == "" end)
  end

  defp sync_row(row, cols, tournament, stages_map) do
    with {:ok, match_id} <- get_col(row, cols, "matchid"),
         {:ok, group} <- get_col(row, cols, "grupo"),
         {:ok, raw_fecha} <- get_col(row, cols, "fecha"),
         {:ok, home_name} <- get_col(row, cols, "local"),
         {:ok, away_name} <- get_col(row, cols, "visitante") do
      hora = get_optional_col(row, cols, "hora")
      kickoff_at = parse_kickoff(raw_fecha, hora)
      home_score = parse_score(get_optional_col(row, cols, "goleslocal"))
      away_score = parse_score(get_optional_col(row, cols, "golesvisitante"))
      finalizado = get_optional_col(row, cols, "finalizado")
      stage_id = resolve_stage_id(stages_map, group)
      api_id = synthetic_id(match_id)

      home_team = upsert_team(tournament.id, home_name, group)
      away_team = upsert_team(tournament.id, away_name, group)

      attrs = %{
        api_football_id: api_id,
        tournament_id: tournament.id,
        stage_id: stage_id,
        home_team_id: home_team.id,
        away_team_id: away_team.id,
        round: "Group #{group}",
        kickoff_at: kickoff_at,
        prediction_lock_at: DateTime.add(kickoff_at, -15, :minute),
        status: infer_status(home_score, away_score, kickoff_at, finalizado),
        home_score: home_score,
        away_score: away_score
      }

      upsert_match(attrs)
    else
      {:skip, reason} ->
        Logger.debug("ExcelImporter: skipping row — #{reason}")
        :skip

      {:error, reason} ->
        Logger.warning("ExcelImporter: error on row — #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp get_col(row, cols, name) do
    case Map.fetch(cols, name) do
      {:ok, idx} ->
        case Enum.at(row, idx) do
          nil -> {:skip, "#{name} is nil"}
          "" -> {:skip, "#{name} is empty"}
          value -> {:ok, value}
        end

      :error ->
        {:skip, "column '#{name}' not found in headers"}
    end
  end

  defp get_optional_col(row, cols, name) do
    case Map.fetch(cols, name) do
      {:ok, idx} -> Enum.at(row, idx)
      :error -> nil
    end
  end

  # Converts MatchID like "A1", "L6" to a stable integer.
  # Formula: (group_index * 100) + match_number  →  A1=101, A6=106, L6=1206
  defp synthetic_id(match_id) when is_binary(match_id) do
    <<letter::utf8, rest::binary>> = String.trim(match_id)
    group_index = letter - ?A + 1
    match_num = String.to_integer(rest)
    group_index * 100 + match_num
  end

  defp resolve_stage_id(stages_map, group_letter) when is_binary(group_letter) do
    slug = "group_#{String.downcase(String.trim(group_letter))}"
    Map.get(stages_map, slug)
  end

  defp upsert_team(tournament_id, name, group) when is_binary(name) do
    name = String.trim(name)
    code = make_code(name)
    group = String.trim(group)

    case Repo.get_by(Team, tournament_id: tournament_id, code: code) do
      nil ->
        Repo.insert!(%Team{
          tournament_id: tournament_id,
          name: name,
          code: code,
          group: group
        })

      existing ->
        if is_nil(existing.group) do
          existing |> Ecto.Changeset.change(group: group) |> Repo.update!()
        else
          existing
        end
    end
  end

  defp upsert_match(attrs) do
    result =
      %Match{}
      |> Match.sync_changeset(attrs)
      |> Repo.insert(
        on_conflict:
          {:replace,
           [:status, :home_score, :away_score, :kickoff_at, :prediction_lock_at, :updated_at]},
        conflict_target: :api_football_id,
        returning: true
      )

    case result do
      {:ok, match} ->
        Phoenix.PubSub.broadcast(Prode.PubSub, "match:#{match.id}", {:match_updated, match})

        if match.status == :finished do
          %{"match_id" => match.id}
          |> Prode.Workers.PointsCalculator.new()
          |> Oban.insert()
        end

        {:ok, match}

      {:error, changeset} ->
        Logger.warning("ExcelImporter: failed to upsert match #{attrs.api_football_id}: #{inspect(changeset.errors)}")
        {:error, changeset.errors}
    end
  end

  # Argentina is UTC-3 year-round (no DST). Add 3h to convert ART → UTC.
  @art_offset_seconds 3 * 3600

  # parse_kickoff/2: combines a date/datetime value with an optional Hora cell.
  # When Hora is present, it overrides any time component already in Fecha.
  defp parse_kickoff(fecha, hora) do
    base_dt = parse_to_naive(fecha)

    naive_with_time =
      case hora do
        nil ->
          base_dt

        h ->
          time = parse_time(h)
          NaiveDateTime.new!(NaiveDateTime.to_date(base_dt), Time.new!(time.hour, time.minute, 0))
      end

    naive_with_time
    |> DateTime.from_naive!("Etc/UTC")
    |> DateTime.add(@art_offset_seconds, :second)
    |> DateTime.truncate(:second)
  end

  # Converts any Fecha value to NaiveDateTime (time defaults to 00:00 if date-only).
  defp parse_to_naive(%NaiveDateTime{} = ndt), do: ndt
  defp parse_to_naive(%DateTime{} = dt), do: DateTime.to_naive(dt)

  defp parse_to_naive(%Date{} = d), do: NaiveDateTime.new!(d, ~T[00:00:00])

  defp parse_to_naive(value) when is_binary(value) do
    value = String.trim(value)

    cond do
      # Full ISO datetime with offset — strip offset, keep naive local time
      match?({:ok, _, _}, DateTime.from_iso8601(value)) ->
        {:ok, dt, _} = DateTime.from_iso8601(value)
        DateTime.to_naive(dt)

      # NaiveDateTime string: "2026-06-11 18:00:00" or "2026-06-11T18:00:00"
      match?({:ok, _}, NaiveDateTime.from_iso8601(value)) ->
        {:ok, ndt} = NaiveDateTime.from_iso8601(value)
        ndt

      # Date-only string: "2026-06-11"
      match?({:ok, _}, Date.from_iso8601(value)) ->
        {:ok, d} = Date.from_iso8601(value)
        NaiveDateTime.new!(d, ~T[00:00:00])

      true ->
        raise "Cannot parse date/datetime: #{inspect(value)}"
    end
  end

  # Fallback: raw Excel serial-date float (xlsx_reader normally handles these).
  defp parse_to_naive(value) when is_float(value) do
    days = trunc(value)
    epoch = ~D[1899-12-30]
    d = Date.add(epoch, days)
    NaiveDateTime.new!(d, ~T[00:00:00])
  end

  # parse_time/1 — extracts HH:MM from whatever xlsx_reader returns for a time cell.
  defp parse_time(%Time{} = t), do: t

  defp parse_time(%NaiveDateTime{} = ndt), do: NaiveDateTime.to_time(ndt)

  # Excel stores times as floats (fraction of a day). 0.5 = noon.
  defp parse_time(value) when is_float(value) do
    total_seconds = round(value * 86_400)
    h = div(total_seconds, 3600)
    m = div(rem(total_seconds, 3600), 60)
    Time.new!(h, m, 0)
  end

  # String like "16:00" or "16:00:00"
  defp parse_time(value) when is_binary(value) do
    value = String.trim(value)

    case Time.from_iso8601(value) do
      {:ok, t} ->
        t

      _ ->
        case Regex.run(~r/^(\d{1,2}):(\d{2})/, value) do
          [_, h, m] -> Time.new!(String.to_integer(h), String.to_integer(m), 0)
          _ -> raise "Cannot parse time: #{inspect(value)}"
        end
    end
  end

  defp parse_score(nil), do: nil
  defp parse_score(""), do: nil
  defp parse_score(n) when is_integer(n), do: n
  defp parse_score(n) when is_float(n), do: trunc(n)

  defp parse_score(s) when is_binary(s) do
    case Integer.parse(s) do
      {n, _} -> n
      :error -> nil
    end
  end

  # "Finalizado" column wins if present: Y / y / 1 / true / si / sí → :finished
  defp infer_status(_home, _away, _kickoff, finalizado)
       when finalizado in ["Y", "y", "1", "true", "si", "sí", "SI", "SÍ", true, 1],
       do: :finished

  # Fallback: rely on kickoff time having already passed
  defp infer_status(home_score, away_score, kickoff_at, _finalizado) do
    if not is_nil(home_score) and not is_nil(away_score) and
         DateTime.compare(kickoff_at, DateTime.utc_now()) == :lt do
      :finished
    else
      :scheduled
    end
  end

  defp make_code(name) do
    name
    |> String.upcase()
    |> String.replace(~r/[^A-Z]/, "")
    |> String.slice(0, 3)
  end
end
