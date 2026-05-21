defmodule Prode.Matches.Match do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  alias Prode.Tournaments.{Stage, Team, Tournament}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "matches" do
    field :api_football_id, :integer
    field :round, :string
    field :kickoff_at, :utc_datetime
    field :prediction_lock_at, :utc_datetime
    field :locked, :boolean, default: false
    field :status, Ecto.Enum,
      values: [:scheduled, :live, :finished, :postponed, :cancelled],
      default: :scheduled
    field :home_score, :integer
    field :away_score, :integer

    belongs_to :tournament, Tournament
    belongs_to :stage, Stage
    belongs_to :home_team, Team, foreign_key: :home_team_id
    belongs_to :away_team, Team, foreign_key: :away_team_id

    timestamps(type: :utc_datetime)
  end

  def changeset(match, attrs) do
    match
    |> cast(attrs, [
      :api_football_id,
      :round,
      :kickoff_at,
      :prediction_lock_at,
      :locked,
      :status,
      :home_score,
      :away_score,
      :tournament_id,
      :stage_id,
      :home_team_id,
      :away_team_id
    ])
    |> validate_required([:api_football_id, :kickoff_at, :prediction_lock_at, :tournament_id,
                           :home_team_id, :away_team_id])
    |> unique_constraint(:api_football_id)
    |> foreign_key_constraint(:tournament_id)
    |> foreign_key_constraint(:stage_id)
    |> foreign_key_constraint(:home_team_id)
    |> foreign_key_constraint(:away_team_id)
  end

  def sync_changeset(match, attrs) do
    match
    |> changeset(attrs)
  end
end
