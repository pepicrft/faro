defmodule Faro.Auth.RegistrationTest do
  use ExUnit.Case, async: true
  alias Faro.Auth.Registration

  test "native callbacks allow HTTPS, IP loopback, and reverse-domain schemes" do
    for uri <- [
          "https://example.com/callback",
          "com.example:/callback",
          "http://127.0.0.1:49152/callback",
          "http://[::1]:49152/callback",
          "io.github.pepicrft.faro:/oauth/callback"
        ] do
      assert Registration.valid_redirect?(uri), uri
    end
  end

  test "rejects unsafe and ambiguous redirect URIs" do
    for uri <- [
          nil,
          123,
          "",
          "https://",
          "https://example.com:garbage/cb",
          "//example.com/cb",
          "http://localhost/cb",
          "http://192.168.1.1/cb",
          "http://example.com/cb",
          "https://user:password@example.com/cb",
          "https://example.com/cb#fragment",
          "https://*.example.com/cb",
          "https://example.com/*",
          "https://example.com;script-src/cb",
          "https://example.com'unsafe-inline'/cb",
          "javascript:alert(1)",
          "file:///tmp/cb",
          "faro:/cb",
          "io.github.faro:\\callback",
          "https://example.com/\r\nset-cookie:test"
        ] do
      refute Registration.valid_redirect?(uri), inspect(uri)
    end
  end

  test "client policy cannot be overridden by untrusted registration metadata" do
    params = %{
      "redirect_uris" => ["io.github.pepicrft.faro:/callback"],
      "confidential" => true,
      "pkce" => false,
      "public_refresh_token" => false,
      "supported_grant_types" => ["password"],
      "jwks_uri" => "http://127.0.0.1/admin",
      "private_key" => "attacker",
      "access_token_ttl" => 999_999
    }

    assert {:ok, metadata} = Registration.normalize(params)
    assert metadata.pkce
    refute metadata.confidential
    assert metadata.public_refresh_token
    assert metadata.supported_grant_types == ["authorization_code", "refresh_token", "revoke"]
    refute Map.has_key?(metadata, :jwks_uri)
    refute Map.has_key?(metadata, :private_key)
    refute Map.has_key?(metadata, :access_token_ttl)
  end

  test "rejects unsupported grants, client secrets, scopes, and malformed metadata" do
    base = %{"redirect_uris" => ["https://example.com/cb"]}

    for params <- [
          %{"grant_types" => ["client_credentials"]},
          %{"grant_types" => "authorization_code"},
          %{"response_types" => ["token"]},
          %{"token_endpoint_auth_method" => "client_secret_post"},
          %{"scope" => "openid admin"},
          %{"scope" => []},
          %{"client_name" => []},
          %{"redirect_uris" => []},
          %{"redirect_uris" => [123]}
        ] do
      assert {:error, _} = Registration.normalize(Map.merge(base, params))
    end
  end

  test "authorization requires S256 PKCE, openid, and bounded unpredictable state" do
    params = %{
      "client_id" => Ecto.UUID.generate(),
      "redirect_uri" => "http://127.0.0.1:4567/cb",
      "response_type" => "code",
      "scope" => "openid email",
      "state" => String.duplicate("s", 32),
      "code_challenge" => String.duplicate("c", 43),
      "code_challenge_method" => "S256"
    }

    assert {:ok, ^params} = Registration.authorization(params)

    for override <- [
          %{"code_challenge_method" => "plain"},
          %{"code_challenge" => "short"},
          %{"state" => "short"},
          %{"state" => String.duplicate("s", 513)},
          %{"response_type" => "token"},
          %{"redirect_uri" => "http://127.0.0.1:4567/cb\n"},
          %{"prompt" => "none"},
          %{"request_uri" => "http://127.0.0.1/secret"},
          %{"response_mode" => "fragment"},
          %{"scope" => "email"},
          %{"scope" => ["openid"]}
        ] do
      assert {:error, _} = Registration.authorization(Map.merge(params, override))
    end
  end
end
