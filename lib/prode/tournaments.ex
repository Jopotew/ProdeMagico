defmodule Prode.Tournaments do
  @moduledoc """
  Context for tournament, stage, and team data.
  """

  import Ecto.Query, warn: false

  alias Prode.Repo
  alias Prode.Tournaments.{Stage, Team, Tournament}

  @doc "Gets a tournament by id. Raises `Ecto.NoResultsError` if not found."
  def get_tournament!(id), do: Repo.get!(Tournament, id)

  @doc "Gets a tournament by season year. Raises `Ecto.NoResultsError` if not found."
  def get_tournament_by_season!(season), do: Repo.get_by!(Tournament, season: season)

  @doc "Returns all tournaments with status `:active`."
  def list_active_tournaments do
    Repo.all(from t in Tournament, where: t.status == :active)
  end

  @doc "Returns stages for a tournament ordered by `order` ascending."
  def list_stages(tournament_id) do
    Repo.all(from s in Stage, where: s.tournament_id == ^tournament_id, order_by: s.order)
  end

  @doc "Returns all teams for a tournament."
  def list_teams(tournament_id) do
    Repo.all(from t in Team, where: t.tournament_id == ^tournament_id, order_by: t.name)
  end

  @doc "Returns teams in a specific group for a tournament."
  def list_teams_by_group(tournament_id, group) do
    Repo.all(
      from t in Team,
        where: t.tournament_id == ^tournament_id and t.group == ^group,
        order_by: t.name
    )
  end

  @doc "Returns the current tournament (active or upcoming). Raises if none found."
  def get_active_tournament! do
    Repo.one!(
      from t in Tournament,
        where: t.status in [:active, :upcoming],
        order_by: t.starts_on,
        limit: 1
    )
  end

  @doc "Returns the current or next upcoming tournament (lowest start date among upcoming/active)."
  def get_current_tournament do
    from(t in Tournament,
      where: t.status in [:upcoming, :active],
      order_by: t.starts_on,
      limit: 1
    )
    |> Repo.one()
  end

  @doc "Sets bonus_predictions_lock_at to now (call when tournament has started and lock should apply)."
  def set_bonus_predictions_lock!(%Tournament{} = tournament) do
    tournament
    |> Ecto.Changeset.change(
      bonus_predictions_lock_at: DateTime.utc_now() |> DateTime.truncate(:second)
    )
    |> Repo.update!()
  end
end
