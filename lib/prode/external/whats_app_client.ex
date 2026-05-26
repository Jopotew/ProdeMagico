defmodule Prode.External.WhatsAppClient do
  @moduledoc "Behaviour for the WhatsApp Cloud API client so tests can swap in a Mox mock."

  @callback send_template(phone_number :: String.t(), template_name :: String.t(), params :: list()) ::
              :ok | {:error, term()}
end
