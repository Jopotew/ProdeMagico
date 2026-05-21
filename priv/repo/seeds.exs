alias Prode.Repo
alias Prode.Tournaments.{Stage, Tournament}

# --- World Cup 2026 tournament ---

tournament =
  case Repo.get_by(Tournament, season: 2026) do
    nil ->
      Repo.insert!(%Tournament{
        name: "FIFA World Cup",
        season: 2026,
        status: :upcoming,
        starts_on: ~D[2026-06-11],
        ends_on: ~D[2026-07-19]
      })

    existing ->
      existing
  end

IO.puts("Tournament: #{tournament.name} #{tournament.season} (#{tournament.id})")

# --- Stages ---

stages = [
  # Group stage — 8 groups, multiplier 1.0
  %{name: "Group A", slug: "group_a", type: :group, points_multiplier: 1.0, order: 1},
  %{name: "Group B", slug: "group_b", type: :group, points_multiplier: 1.0, order: 2},
  %{name: "Group C", slug: "group_c", type: :group, points_multiplier: 1.0, order: 3},
  %{name: "Group D", slug: "group_d", type: :group, points_multiplier: 1.0, order: 4},
  %{name: "Group E", slug: "group_e", type: :group, points_multiplier: 1.0, order: 5},
  %{name: "Group F", slug: "group_f", type: :group, points_multiplier: 1.0, order: 6},
  %{name: "Group G", slug: "group_g", type: :group, points_multiplier: 1.0, order: 7},
  %{name: "Group H", slug: "group_h", type: :group, points_multiplier: 1.0, order: 8},
  # Knockout stages — multiplier 2.0
  %{name: "Round of 16", slug: "r16", type: :knockout, points_multiplier: 2.0, order: 9},
  %{name: "Quarter-finals", slug: "qf", type: :knockout, points_multiplier: 2.0, order: 10},
  %{name: "Semi-finals", slug: "sf", type: :knockout, points_multiplier: 2.0, order: 11},
  %{name: "Third place", slug: "third", type: :knockout, points_multiplier: 2.0, order: 12},
  %{name: "Final", slug: "final", type: :knockout, points_multiplier: 2.0, order: 13}
]

Enum.each(stages, fn attrs ->
  case Repo.get_by(Stage, tournament_id: tournament.id, slug: attrs.slug) do
    nil ->
      Repo.insert!(struct(Stage, Map.put(attrs, :tournament_id, tournament.id)))
      IO.puts("  Created stage: #{attrs.name}")

    _existing ->
      IO.puts("  Skipped stage: #{attrs.name} (already exists)")
  end
end)

IO.puts("Seed complete.")
