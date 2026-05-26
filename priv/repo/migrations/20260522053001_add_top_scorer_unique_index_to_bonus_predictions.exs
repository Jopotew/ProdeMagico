defmodule Prode.Repo.Migrations.AddTopScorerUniqueIndexToBonusPredictions do
  use Ecto.Migration

  def change do
    create unique_index(
             :bonus_predictions,
             [:user_id, :tournament_id, :kind],
             where: "kind = 'top_scorer'",
             name: :bonus_predictions_top_scorer_unique_index
           )
  end
end
