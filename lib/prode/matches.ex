defmodule Prode.Matches do
  @moduledoc """
  Context for match data and lifecycle management.
  """

  import Ecto.Query, warn: false

  alias Prode.Matches.Match
  alias Prode.Repo

  @doc "Gets a single match. Raises `Ecto.NoResultsError` if not found."
  def get_match!(id), do: Repo.get!(Match, id)

  @doc "Returns all matches for a tournament, ordered by kickoff time."
  def list_matches_for_tournament(tournament_id) do
    Repo.all(
      from m in Match,
        where: m.tournament_id == ^tournament_id,
        order_by: m.kickoff_at
    )
  end

  @doc "Returns upcoming (scheduled, not yet locked) matches."
  def list_upcoming_matches do
    now = DateTime.utc_now()

    Repo.all(
      from m in Match,
        where: m.status == :scheduled and m.locked == false and m.prediction_lock_at > ^now,
        order_by: m.prediction_lock_at
    )
  end

  @doc "Returns true if any match currently has status :live."
  def any_live_matches? do
    Repo.exists?(from m in Match, where: m.status == :live)
  end

  @doc """
  Upserts a match from external API data.
  On conflict with api_football_id, updates status and scores only.
  Broadcasts `{:match_updated, match}` on the match PubSub topic after every upsert.
  """
  def upsert_match(attrs) do
    result =
      %Match{}
      |> Match.sync_changeset(attrs)
      |> Repo.insert(
        on_conflict: {:replace, [:status, :home_score, :away_score, :updated_at]},
        conflict_target: :api_football_id,
        returning: true
      )

    case result do
      {:ok, match} ->
        Phoenix.PubSub.broadcast(Prode.PubSub, "match:#{match.id}", {:match_updated, match})
        {:ok, match}

      error ->
        error
    end
  end

  @doc "Marks a match as locked and broadcasts the update."
  def lock_match!(%Match{} = match) do
    match
    |> Ecto.Changeset.change(locked: true)
    |> Repo.update!()
    |> tap(fn m ->
      Phoenix.PubSub.broadcast(Prode.PubSub, "match:#{m.id}", {:match_updated, m})
    end)
  end
end
