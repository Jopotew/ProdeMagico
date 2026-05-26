alias Prode.Repo
alias Prode.Tournaments.{Stage, Tournament}

# ── World Cup 2026 tournament ──────────────────────────────────────────────

tournament =
  case Repo.get_by(Tournament, season: 2026) do
    nil ->
      Repo.insert!(%Tournament{
        name: "FIFA World Cup",
        season: 2026,
        status: :active,
        starts_on: ~D[2026-06-11],
        ends_on: ~D[2026-07-19]
      })

    existing ->
      existing
  end

IO.puts("Tournament: #{tournament.name} #{tournament.season} (#{tournament.id})")

# ── Stages ─────────────────────────────────────────────────────────────────
# WC 2026: 12 groups (A-L), 48 teams, Round of 32 added before R16

stages = [
  %{name: "Group A", slug: "group_a", type: :group, points_multiplier: 1.0, order: 1},
  %{name: "Group B", slug: "group_b", type: :group, points_multiplier: 1.0, order: 2},
  %{name: "Group C", slug: "group_c", type: :group, points_multiplier: 1.0, order: 3},
  %{name: "Group D", slug: "group_d", type: :group, points_multiplier: 1.0, order: 4},
  %{name: "Group E", slug: "group_e", type: :group, points_multiplier: 1.0, order: 5},
  %{name: "Group F", slug: "group_f", type: :group, points_multiplier: 1.0, order: 6},
  %{name: "Group G", slug: "group_g", type: :group, points_multiplier: 1.0, order: 7},
  %{name: "Group H", slug: "group_h", type: :group, points_multiplier: 1.0, order: 8},
  %{name: "Group I", slug: "group_i", type: :group, points_multiplier: 1.0, order: 9},
  %{name: "Group J", slug: "group_j", type: :group, points_multiplier: 1.0, order: 10},
  %{name: "Group K", slug: "group_k", type: :group, points_multiplier: 1.0, order: 11},
  %{name: "Group L", slug: "group_l", type: :group, points_multiplier: 1.0, order: 12},
  %{name: "Round of 32", slug: "r32", type: :knockout, points_multiplier: 2.0, order: 13},
  %{name: "Round of 16", slug: "r16", type: :knockout, points_multiplier: 2.0, order: 14},
  %{name: "Quarter-finals", slug: "qf", type: :knockout, points_multiplier: 2.0, order: 15},
  %{name: "Semi-finals", slug: "sf", type: :knockout, points_multiplier: 2.0, order: 16},
  %{name: "Third place", slug: "third", type: :knockout, points_multiplier: 2.0, order: 17},
  %{name: "Final", slug: "final", type: :knockout, points_multiplier: 2.0, order: 18}
]

Enum.each(stages, fn attrs ->
  case Repo.get_by(Stage, tournament_id: tournament.id, slug: attrs.slug) do
    nil ->
      Repo.insert!(struct(Stage, Map.put(attrs, :tournament_id, tournament.id)))
      IO.puts("  Created stage: #{attrs.name}")

    existing ->
      # Update order/name if needed (in case of re-seeding with new structure)
      existing
      |> Ecto.Changeset.change(Map.take(attrs, [:name, :order]))
      |> Repo.update!()

      IO.puts("  OK stage: #{attrs.name}")
  end
end)

IO.puts("\nSeeds complete. Run `mix prode.import_matches` to load fixtures from docs/matches.xlsx")
