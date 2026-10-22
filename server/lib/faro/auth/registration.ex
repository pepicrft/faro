defmodule Faro.Auth.Registration do
  @moduledoc "Restrictive RFC 7591 metadata policy for public native clients."
  @scopes ~w(openid profile email)
  @grants ~w(authorization_code refresh_token)

  def normalize(params) when is_map(params) do
    redirects = params["redirect_uris"]
    name = params["client_name"] || "Faro native client"
    grants = Map.get(params, "grant_types", @grants)
    scope = Map.get(params, "scope", "openid profile email")

    cond do
      not is_list(redirects) or length(redirects) not in 1..10 ->
        {:error, "Provide between one and ten redirect URIs."}

      not Enum.all?(redirects, &valid_redirect?/1) ->
        {:error,
         "Use HTTPS, an IP loopback HTTP URI, or a reverse-domain native scheme without fragments or credentials."}

      not is_binary(name) or byte_size(name) not in 1..120 ->
        {:error, "client_name must be between 1 and 120 bytes."}

      not is_list(grants) or "authorization_code" not in grants or
          Enum.any?(grants, &(&1 not in @grants)) ->
        {:error, "Only authorization_code and optional refresh_token grants are supported."}

      Map.get(params, "response_types", ["code"]) != ["code"] ->
        {:error, "Only the code response type is supported."}

      Map.get(params, "token_endpoint_auth_method", "none") != "none" ->
        {:error, "Native clients must use token_endpoint_auth_method none."}

      Map.get(params, "id_token_signed_response_alg", "RS256") != "RS256" ->
        {:error, "ID tokens use RS256 signatures."}

      Map.get(params, "application_type", "native") != "native" ->
        {:error, "Only native applications are supported."}

      not is_binary(scope) or byte_size(scope) > 128 ->
        {:error, "Invalid scope."}

      Enum.any?(String.split(scope), &(&1 not in @scopes)) or "openid" not in String.split(scope) ->
        {:error, "Scopes must include openid and may include profile and email."}

      true ->
        {:ok,
         %{
           name: name,
           redirect_uris: Enum.uniq(redirects),
           supported_grant_types: Enum.uniq(grants) ++ ["revoke"],
           confidential: false,
           pkce: true,
           id_token_signature_alg: "RS256",
           public_refresh_token: true,
           public_revoke: true,
           authorize_scope: true,
           token_endpoint_auth_methods: [],
           authorized_scopes: Enum.map(String.split(scope), &%{name: &1, public: true}),
           metadata: %{"grant_types" => Enum.uniq(grants), "scope" => scope}
         }}
    end
  end

  def valid_redirect?(value) when is_binary(value) and byte_size(value) in 1..1024 do
    with {:ok, uri} <- URI.new(value) do
      safe =
        is_nil(uri.fragment) and is_nil(uri.userinfo) and
          not String.contains?(value, ["\r", "\n", "\\", "*"])

      safe and
        case uri do
          %URI{scheme: "https", host: host} when is_binary(host) and host != "" ->
            Regex.match?(~r/^[A-Za-z0-9.-]+$/, host) or
              match?({:ok, _}, :inet.parse_address(String.to_charlist(host)))

          %URI{scheme: "http", host: host} when host in ["127.0.0.1", "::1"] ->
            true

          %URI{scheme: scheme, host: nil, path: "/" <> _} when is_binary(scheme) ->
            Regex.match?(~r/^[a-z][a-z0-9+\-]*(?:\.[a-z0-9+\-]+){1,}$/, scheme)

          _ ->
            false
        end
    else
      _ -> false
    end
  end

  def valid_redirect?(_), do: false

  def authorization(params) do
    unsupported = Enum.any?(~w(request request_uri prompt max_age), &Map.has_key?(params, &1))
    mode = Map.get(params, "response_mode", "query")

    params =
      Map.take(
        params,
        ~w(client_id redirect_uri response_type scope state nonce code_challenge code_challenge_method)
      )

    scope = Map.get(params, "scope", "openid")

    with false <- unsupported,
         "query" <- mode,
         true <- valid_redirect?(params["redirect_uri"]),
         true <- Enum.all?(params, fn {_, v} -> is_binary(v) and byte_size(v) <= 1024 end),
         true <- byte_size(URI.encode_query(params)) <= 2400,
         "code" <- params["response_type"],
         "S256" <- params["code_challenge_method"],
         challenge when is_binary(challenge) <- params["code_challenge"],
         true <- Regex.match?(~r/^[A-Za-z0-9_-]{43}$/, challenge),
         state when is_binary(state) <- params["state"],
         true <- byte_size(state) in 16..512,
         true <- "openid" in String.split(scope),
         true <- Enum.all?(String.split(scope), &(&1 in @scopes)) do
      {:ok, Map.put(params, "scope", scope)}
    else
      _ ->
        {:error,
         "Use response_type code, S256 PKCE, openid scope, and a random state of 16 to 512 bytes."}
    end
  end
end
