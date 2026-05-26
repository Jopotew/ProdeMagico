defmodule Mix.Tasks.Prode.ImportMatches do
  @shortdoc "Imports WC 2026 fixtures from docs/matches.xlsx into the database."
  @moduledoc """
  Parses the Partidos sheet in docs/matches.xlsx and upserts teams + matches.

  Usage:
      mix prode.import_matches
      mix prode.import_matches --file path/to/other.xlsx
  """

  use Mix.Task

  @requirements ["app.start"]

  @impl Mix.Task
  def run(args) do
    path =
      case Enum.find_index(args, &(&1 == "--file")) do
        nil -> Path.join([File.cwd!(), "docs", "matches.xlsx"])
        idx -> Enum.at(args, idx + 1)
      end

    unless File.exists?(path) do
      Mix.raise("File not found: #{path}")
    end

    IO.puts("=== Prode Match Import ===")
    IO.puts("Reading #{path}...")

    case Prode.Matches.ExcelImporter.import_from_file(path) do
      {:ok, %{synced: ok, skipped: skipped, errors: errors, total: total}} ->
        IO.puts("Done: #{ok}/#{total} synced, #{skipped} skipped, #{errors} errors.")

      {:error, reason} ->
        Mix.raise("Import failed: #{inspect(reason)}")
    end
  end
end
