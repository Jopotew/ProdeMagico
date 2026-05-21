defmodule Prode.External.WhatsApp do
  @moduledoc """
  Thin client for Meta's WhatsApp Cloud API.
  Sends pre-approved template messages only.
  """

  require Logger

  @api_version "v19.0"

  @doc "Sends a WhatsApp template message to the given phone number."
  def send_template(phone_number, template_name, params \\ []) do
    phone_id = Application.fetch_env!(:prode, :whatsapp_phone_number_id)
    token = Application.fetch_env!(:prode, :whatsapp_access_token)
    base_url = Application.get_env(:prode, :whatsapp_base_url, "https://graph.facebook.com")

    components =
      if params == [] do
        []
      else
        [
          %{
            "type" => "body",
            "parameters" =>
              Enum.map(params, fn text -> %{"type" => "text", "text" => to_string(text)} end)
          }
        ]
      end

    body = %{
      "messaging_product" => "whatsapp",
      "to" => normalize_phone(phone_number),
      "type" => "template",
      "template" => %{
        "name" => template_name,
        "language" => %{"code" => "es_AR"},
        "components" => components
      }
    }

    case Req.post("#{base_url}/#{@api_version}/#{phone_id}/messages",
           json: body,
           headers: [{"Authorization", "Bearer #{token}"}],
           retry: false
         ) do
      {:ok, %{status: 200}} ->
        :ok

      {:ok, %{status: status, body: resp_body}} ->
        Logger.warning("WhatsApp API returned #{status}: #{inspect(resp_body)}")
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp normalize_phone("+" <> rest), do: rest
  defp normalize_phone(phone), do: phone
end
