defmodule Faro.Auth.RateLimit do
  @moduledoc "PostgreSQL-backed fixed windows shared by all server replicas."
  use Faro.Schema
  import Ecto.Query

  schema "auth_rate_limits" do
    field(:key, :string)
    field(:window, :integer)
    field(:attempts, :integer, default: 1)
  end

  def allow?(key, limit, seconds \\ 60, now \\ System.system_time(:second)) do
    window = div(now, seconds)
    key = :crypto.hash(:sha256, key) |> Base.encode16(case: :lower)
    bucket = %__MODULE__{key: key, window: window}

    {:ok, bucket} =
      Faro.Repo.insert(bucket,
        on_conflict: [inc: [attempts: 1]],
        conflict_target: [:key, :window],
        returning: true,
        log: false
      )

    # Bound storage without a background process or in-memory authorization state.
    Faro.Repo.delete_all(from(b in __MODULE__, where: b.window < ^(window - 1440)), log: false)
    bucket.attempts <= limit
  end
end
