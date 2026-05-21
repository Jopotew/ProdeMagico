defmodule Prode.Factory do
  @moduledoc false
  use ExMachina.Ecto, repo: Prode.Repo

  alias Prode.Accounts.User
  alias Prode.Groups.{Group, Membership}
  alias Prode.Matches.Match
  alias Prode.Predictions.{BonusPrediction, Prediction}
  alias Prode.Tournaments.{Stage, Team, Tournament}

  def user_factory do
    %User{
      email: sequence(:email, &"user#{&1}@example.com"),
      confirmed_at: DateTime.utc_now(:second)
    }
  end

  def tournament_factory do
    %Tournament{
      name: "FIFA World Cup",
      season: sequence(:season, fn n -> 2030 + n end),
      status: :upcoming,
      starts_on: ~D[2026-06-11],
      ends_on: ~D[2026-07-19]
    }
  end

  def stage_factory do
    n = sequence(:stage_n, & &1)

    %Stage{
      name: "Group #{n}",
      slug: "group_#{n}",
      type: :group,
      points_multiplier: 1.0,
      order: n,
      tournament: build(:tournament)
    }
  end

  def knockout_stage_factory do
    %Stage{
      name: "Round of 16",
      slug: "r16",
      type: :knockout,
      points_multiplier: 2.0,
      order: 10,
      tournament: build(:tournament)
    }
  end

  def team_factory do
    %Team{
      name: sequence(:team_name, &"Team #{&1}"),
      code: sequence(:team_code, &"T#{String.pad_leading(to_string(&1), 2, "0")}"),
      group: "A",
      tournament: build(:tournament)
    }
  end

  def match_factory do
    now = DateTime.utc_now(:second)

    %Match{
      api_football_id: sequence(:api_football_id, & &1),
      round: "Group Stage - 1",
      kickoff_at: DateTime.add(now, 1, :day),
      prediction_lock_at: DateTime.add(now, 23, :hour) |> DateTime.add(45, :minute),
      locked: false,
      status: :scheduled,
      tournament: build(:tournament),
      home_team: build(:team),
      away_team: build(:team)
    }
  end

  def prediction_factory do
    %Prediction{
      home_score: 1,
      away_score: 0,
      user: build(:user),
      match: build(:match)
    }
  end

  def group_factory do
    %Group{
      name: sequence(:group_name, &"Grupo #{&1}"),
      invite_code: sequence(:invite_code, fn n -> String.pad_leading(to_string(n), 6, "0") |> String.upcase() end),
      max_members: 50,
      owner: build(:user),
      tournament: build(:tournament)
    }
  end

  def membership_factory do
    %Membership{
      role: :member,
      joined_at: DateTime.utc_now(:second),
      user: build(:user),
      group: build(:group)
    }
  end

  def bonus_prediction_factory do
    %BonusPrediction{
      kind: :top_scorer,
      payload: %{"player_id" => 1},
      user: build(:user),
      tournament: build(:tournament)
    }
  end
end
