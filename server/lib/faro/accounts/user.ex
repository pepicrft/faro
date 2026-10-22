defmodule Faro.Accounts.User do
  @moduledoc false
  use Faro.Schema
  import Ecto.Changeset

  @derive {Inspect, except: [:password, :password_hash]}
  schema "users" do
    field(:email, :string)
    field(:password_hash, :string, redact: true)
    field(:password, :string, virtual: true, redact: true)
    timestamps(type: :utc_datetime_usec)
  end

  def registration_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:email, :password])
    |> update_change(:email, &(String.trim(&1) |> String.downcase()))
    |> validate_required([:email, :password])
    |> validate_length(:email, max: 254)
    |> validate_format(:email, ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/u)
    |> validate_length(:password, min: 15, max: 128)
    |> unique_constraint(:email)
    |> hash_password()
  end

  defp hash_password(%Ecto.Changeset{valid?: true} = changeset) do
    put_change(
      changeset,
      :password_hash,
      Pbkdf2.hash_pwd_salt(get_change(changeset, :password), rounds: 210_000, digest: :sha512)
    )
    |> delete_change(:password)
  end

  defp hash_password(changeset), do: changeset
end
