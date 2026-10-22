defmodule Faro.AuthenticationTest do
  use ExUnit.Case, async: true
  import Phoenix.ConnTest
  import Plug.Conn
  import Ecto.Query
  @endpoint FaroWeb.Endpoint
  @moduletag :database

  setup do
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(Faro.Repo, shared: false)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(owner) end)
    namespace = Ecto.UUID.generate()
    # Use the real database-backed limiter with an explicitly isolated namespace.
    limiter = fn key, limit -> Faro.Auth.RateLimit.allow?(namespace <> key, limit) end
    %{limiter: limiter}
  end

  defp fresh(ctx),
    do:
      build_conn()
      |> put_private(:auth_rate_limiter, ctx.limiter)
      |> put_private(:plug_skip_csrf_protection, false)

  defp next(conn, ctx),
    do:
      recycle(conn)
      |> put_private(:auth_rate_limiter, ctx.limiter)
      |> put_private(:plug_skip_csrf_protection, false)

  defp csrf(conn) do
    [_, token] = Regex.run(~r/name="_csrf_token" value="([^"]+)"/, conn.resp_body)
    token
  end

  defp request_id(conn) do
    [_, id] = Regex.run(~r/name="request_id" value="([^"]+)"/, conn.resp_body)
    id
  end

  defp json_post(ctx, path, params) do
    fresh(ctx)
    |> put_req_header("content-type", "application/json")
    |> post(path, Jason.encode!(params))
  end

  defp register_client(ctx, overrides \\ %{}) do
    conn =
      json_post(
        ctx,
        "/oauth/register",
        Map.merge(
          %{
            "client_name" => "Test client",
            "redirect_uris" => ["http://127.0.0.1:54321/callback"]
          },
          overrides
        )
      )

    assert conn.status == 201, conn.resp_body
    {Jason.decode!(conn.resp_body), conn}
  end

  defp user(ctx) do
    conn = fresh(ctx) |> get("/auth/login")
    password = "a unique long test password"
    email = "#{Ecto.UUID.generate()}@example.com"

    signed_in =
      next(conn, ctx)
      |> post("/auth/register", %{
        "email" => email,
        "password" => password,
        "_csrf_token" => csrf(conn)
      })

    assert signed_in.status == 302, signed_in.resp_body
    {signed_in, email, password}
  end

  defp authorization(client, overrides \\ %{}) do
    verifier = :crypto.strong_rand_bytes(48) |> Base.url_encode64(padding: false)

    params = %{
      "client_id" => client["client_id"],
      "redirect_uri" => hd(client["redirect_uris"]),
      "response_type" => "code",
      "scope" => "openid email",
      "state" => Ecto.UUID.generate(),
      "nonce" => Ecto.UUID.generate(),
      "code_challenge_method" => "S256",
      "code_challenge" => :crypto.hash(:sha256, verifier) |> Base.url_encode64(padding: false)
    }

    {Map.merge(params, overrides), verifier}
  end

  defp consent(conn, ctx, params, decision \\ "approve") do
    form = next(conn, ctx) |> get("/oauth/authorize", params)
    assert form.status == 200, form.resp_body

    next(form, ctx)
    |> post("/oauth/authorize", %{
      "decision" => decision,
      "request_id" => request_id(form),
      "_csrf_token" => csrf(form)
    })
  end

  defp grant(ctx) do
    {client, _} = register_client(ctx)
    {browser, email, _password} = user(ctx)
    {params, verifier} = authorization(client)
    approved = consent(browser, ctx, params)
    assert approved.status == 302, approved.resp_body
    uri = approved |> get_resp_header("location") |> hd() |> URI.parse()
    result = URI.decode_query(uri.query)
    assert result["state"] == params["state"]
    assert result["code"]

    exchange = %{
      "grant_type" => "authorization_code",
      "client_id" => client["client_id"],
      "code" => result["code"],
      "redirect_uri" => params["redirect_uri"],
      "code_verifier" => verifier
    }

    {exchange, client, browser, email, params}
  end

  defp exchange(ctx, params) do
    conn = json_post(ctx, "/oauth/token", params)
    assert conn.status == 200, conn.resp_body
    Jason.decode!(conn.resp_body)
  end

  defp info(ctx, token) do
    fresh(ctx) |> put_req_header("authorization", "Bearer " <> token) |> get("/api/v1/me")
  end

  test "discovery advertises only the supported native flow", ctx do
    conn = fresh(ctx) |> get("/.well-known/openid-configuration")
    metadata = json_response(conn, 200)
    assert metadata["issuer"] == "http://localhost:4002"
    assert metadata["code_challenge_methods_supported"] == ["S256"]
    assert metadata["token_endpoint_auth_methods_supported"] == ["none"]
    assert metadata["response_types_supported"] == ["code"]
  end

  test "DCR persists a public PKCE client without exposing credentials or signing keys", ctx do
    {client, conn} =
      register_client(ctx, %{
        "pkce" => false,
        "confidential" => true,
        "private_key" => "attacker",
        "jwks_uri" => "http://127.0.0.1/private"
      })

    refute Map.has_key?(client, "client_secret")
    refute Map.has_key?(client, "private_key")
    assert get_resp_header(conn, "cache-control") == ["no-store"]
    assert client["id_token_signed_response_alg"] == "RS256"
    stored = Faro.Repo.get!(Boruta.Ecto.Client, client["client_id"])
    assert stored.pkce and stored.public_refresh_token and stored.public_revoke
    refute stored.confidential
    assert stored.token_endpoint_auth_methods == []
    assert is_nil(stored.jwks_uri)
    assert stored.supported_grant_types == ["authorization_code", "refresh_token", "revoke"]
    keys = fresh(ctx) |> get("/oauth/jwks") |> json_response(200)
    assert [%{"kty" => "RSA"} = key] = keys["keys"]
    refute Map.has_key?(key, "d")
  end

  test "real PKCE exchange returns an ID token and account-bound bearer credentials", ctx do
    {params, client, _browser, email, request} = grant(ctx)
    tokens = exchange(ctx, params)
    assert is_binary(tokens["refresh_token"])
    assert is_binary(tokens["id_token"])
    assert tokens["expires_in"] in 1..900
    claims = info(ctx, tokens["access_token"]) |> json_response(200)
    assert claims["email"] == email
    refute claims["email_verified"]
    assert {:ok, _} = Ecto.UUID.cast(claims["sub"])

    posted =
      fresh(ctx)
      |> put_req_header("authorization", "Bearer " <> tokens["access_token"])
      |> post("/oauth/userinfo", %{})

    assert json_response(posted, 200) == claims
    keys = fresh(ctx) |> get("/oauth/jwks") |> json_response(200)
    jwk = keys["keys"] |> hd() |> JOSE.JWK.from_map()
    assert {true, jwt, _} = JOSE.JWT.verify_strict(jwk, ["RS256"], tokens["id_token"])
    assert jwt.fields["iss"] == "http://localhost:4002"
    assert jwt.fields["aud"] == client["client_id"]
    assert jwt.fields["sub"] == claims["sub"]
    assert jwt.fields["nonce"] == request["nonce"]
    assert json_post(ctx, "/oauth/token", params).status == 400
  end

  test "wrong verifier, wrong client, and wrong redirect never consume a valid code", ctx do
    {params, _client, _, _, _} = grant(ctx)
    {other, _} = register_client(ctx)

    for override <- [
          %{"code_verifier" => String.duplicate("x", 64)},
          %{"client_id" => other["client_id"]},
          %{"redirect_uri" => "https://attacker.example/cb"}
        ] do
      assert json_post(ctx, "/oauth/token", Map.merge(params, override)).status in [400, 401]
    end

    assert exchange(ctx, params)["access_token"]
  end

  test "refresh rotates, narrows scope, and reused refresh credentials revoke descendants", ctx do
    {params, client, _, _, _} = grant(ctx)
    initial = exchange(ctx, params)

    refresh = %{
      "grant_type" => "refresh_token",
      "client_id" => client["client_id"],
      "refresh_token" => initial["refresh_token"],
      "scope" => "openid"
    }

    rotated = exchange(ctx, refresh)
    assert rotated["refresh_token"] != initial["refresh_token"]
    claims = info(ctx, rotated["access_token"]) |> json_response(200)
    refute Map.has_key?(claims, "email")
    assert json_post(ctx, "/oauth/token", refresh).status == 400
    assert info(ctx, rotated["access_token"]).status == 401

    assert json_post(ctx, "/oauth/token", %{refresh | "refresh_token" => rotated["refresh_token"]}).status ==
             400
  end

  test "refresh never broadens consent", ctx do
    {params, client, _, _, _} = grant(ctx)
    initial = exchange(ctx, params)

    assert json_post(ctx, "/oauth/token", %{
             "grant_type" => "refresh_token",
             "client_id" => client["client_id"],
             "refresh_token" => initial["refresh_token"],
             "scope" => "openid email admin"
           }).status == 400
  end

  test "revocation invalidates bearer and refresh tokens, including already cached reads", ctx do
    {params, client, _, _, _} = grant(ctx)
    tokens = exchange(ctx, params)
    assert info(ctx, tokens["access_token"]).status == 200

    revoke = %{
      "client_id" => client["client_id"],
      "token" => tokens["refresh_token"],
      "token_type_hint" => "refresh_token"
    }

    assert json_post(ctx, "/oauth/revoke", revoke).status == 200
    assert info(ctx, tokens["access_token"]).status == 401

    assert json_post(ctx, "/oauth/token", %{
             "grant_type" => "refresh_token",
             "client_id" => client["client_id"],
             "refresh_token" => tokens["refresh_token"]
           }).status == 400
  end

  test "unauthenticated requests and expired access tokens are rejected", ctx do
    assert fresh(ctx) |> get("/api/v1/me") |> Map.fetch!(:status) == 401
    assert info(ctx, "not-a-token").status == 401
    {params, _, _, _, _} = grant(ctx)
    tokens = exchange(ctx, params)

    Faro.Repo.update_all(from(t in Boruta.Ecto.Token, where: t.value == ^tokens["access_token"]),
      set: [expires_at: 1]
    )

    assert info(ctx, tokens["access_token"]).status == 401
  end

  test "browser login is CSRF protected and sessions are hashed and revocable", ctx do
    form = fresh(ctx) |> get("/auth/login")

    assert_raise Plug.CSRFProtection.InvalidCSRFTokenError, fn ->
      next(form, ctx)
      |> post("/auth/login", %{"email" => "user@example.com", "password" => "not a password"})
    end

    {browser, email, password} = user(ctx)
    stored = Faro.Repo.get_by!(Faro.Accounts.User, email: email)
    assert stored.password_hash != password
    assert Pbkdf2.verify_pass(password, stored.password_hash)
    refute inspect(stored) =~ stored.password_hash
    session = Faro.Repo.one!(Faro.Accounts.BrowserSession)
    assert byte_size(session.token_hash) == 32
    {client, _} = register_client(ctx)
    {params, _} = authorization(client)
    form = next(browser, ctx) |> get("/oauth/authorize", params)
    logged_out = next(form, ctx) |> post("/auth/logout", %{"_csrf_token" => csrf(form)})
    assert logged_out.status == 302
    assert Faro.Repo.aggregate(Faro.Accounts.BrowserSession, :count) == 0
    stale = next(browser, ctx) |> get("/oauth/authorize", params)
    assert redirected_to(stale) == "/auth/login"
  end

  test "authorization requires explicit consent bound to the rendered request", ctx do
    {client, _} = register_client(ctx)
    {browser, _, _} = user(ctx)
    {params, _} = authorization(client)
    form = next(browser, ctx) |> get("/oauth/authorize", params)
    assert Faro.Repo.aggregate(Boruta.Ecto.Token, :count) == 0

    wrong =
      next(form, ctx)
      |> post("/oauth/authorize", %{
        "decision" => "approve",
        "request_id" => Ecto.UUID.generate(),
        "_csrf_token" => csrf(form)
      })

    assert wrong.status == 400
    denied = consent(browser, ctx, params, "deny")
    assert URI.decode_query(URI.parse(redirected_to(denied)).query)["error"] == "access_denied"
    assert Faro.Repo.aggregate(Boruta.Ecto.Token, :count) == 0
  end

  test "unregistered redirects and PKCE downgrades never redirect or create codes", ctx do
    {client, _} = register_client(ctx)
    {browser, _, _} = user(ctx)
    {params, _} = authorization(client)

    for override <- [
          %{"redirect_uri" => "https://attacker.example/cb"},
          %{"code_challenge_method" => "plain"}
        ] do
      conn = next(browser, ctx) |> get("/oauth/authorize", Map.merge(params, override))
      assert conn.status in [400, 401], conn.resp_body
      assert get_resp_header(conn, "location") == []
    end
  end

  test "login continues the original OAuth request and never accepts an external return URL",
       ctx do
    {client, _} = register_client(ctx)
    {params, _} = authorization(client)
    anonymous = fresh(ctx) |> get("/oauth/authorize", params)
    assert redirected_to(anonymous) == "/auth/login"
    form = next(anonymous, ctx) |> get("/auth/login")

    created =
      next(form, ctx)
      |> post("/auth/register", %{
        "email" => "new@example.com",
        "password" => "a very long unique password",
        "_csrf_token" => csrf(form),
        "return_to" => "https://attacker.example"
      })

    assert redirected_to(created) == "/oauth/authorize"
    consent_form = next(created, ctx) |> get("/oauth/authorize")
    assert consent_form.status == 200
    assert consent_form.resp_body =~ "Test client"
  end

  test "rate limits are enforced atomically without global test state", ctx do
    key = Ecto.UUID.generate()
    assert Faro.Auth.RateLimit.allow?(key, 2)
    assert Faro.Auth.RateLimit.allow?(key, 2)
    refute Faro.Auth.RateLimit.allow?(key, 2)
    for _ <- 1..10, do: assert(fresh(ctx) |> get("/api/v1/me") |> Map.fetch!(:status) == 401)

    blocked =
      build_conn() |> put_private(:auth_rate_limiter, fn _, _ -> false end) |> get("/oauth/jwks")

    assert blocked.status == 429
    assert get_resp_header(blocked, "retry-after") == ["60"]
  end

  test "private-use native callback schemes work through registration and exchange", ctx do
    callback = "io.github.pepicrft.faro:/oauth/callback"
    {client, _} = register_client(ctx, %{"redirect_uris" => [callback]})
    {browser, _, _} = user(ctx)
    {params, verifier} = authorization(client)
    form = next(browser, ctx) |> get("/oauth/authorize", params)
    [policy] = get_resp_header(form, "content-security-policy")
    assert policy =~ "form-action 'self' io.github.pepicrft.faro:"
    assert policy =~ "default-src 'none'"

    approved =
      next(form, ctx)
      |> post("/oauth/authorize", %{
        "decision" => "approve",
        "request_id" => request_id(form),
        "_csrf_token" => csrf(form)
      })

    uri = approved |> redirected_to() |> URI.parse()
    assert uri.scheme == "io.github.pepicrft.faro"
    assert uri.path == "/oauth/callback"
    code = URI.decode_query(uri.query)["code"]

    assert exchange(ctx, %{
             "grant_type" => "authorization_code",
             "client_id" => client["client_id"],
             "code" => code,
             "redirect_uri" => callback,
             "code_verifier" => verifier
           })["access_token"]
  end

  test "expired authorization codes and refresh tokens cannot mint credentials", ctx do
    {params, _, _, _, _} = grant(ctx)

    Faro.Repo.update_all(from(t in Boruta.Ecto.Token, where: t.value == ^params["code"]),
      set: [expires_at: 1]
    )

    assert json_post(ctx, "/oauth/token", params).status == 400

    assert Faro.Repo.aggregate(
             from(t in Boruta.Ecto.Token, where: t.type == "access_token"),
             :count
           ) == 0

    {params, client, _, _, _} = grant(ctx)
    tokens = exchange(ctx, params)
    old = DateTime.add(DateTime.utc_now(), -31 * 86_400)

    Faro.Repo.update_all(from(t in Boruta.Ecto.Token, where: t.value == ^tokens["access_token"]),
      set: [inserted_at: old]
    )

    assert json_post(ctx, "/oauth/token", %{
             "grant_type" => "refresh_token",
             "client_id" => client["client_id"],
             "refresh_token" => tokens["refresh_token"]
           }).status == 400
  end

  test "a different client cannot refresh or revoke another client's credentials", ctx do
    {params, client, _, _, _} = grant(ctx)
    {other, _} = register_client(ctx)
    tokens = exchange(ctx, params)

    refresh = %{
      "grant_type" => "refresh_token",
      "client_id" => other["client_id"],
      "refresh_token" => tokens["refresh_token"]
    }

    assert json_post(ctx, "/oauth/token", refresh).status in [400, 401]

    json_post(ctx, "/oauth/revoke", %{
      "client_id" => other["client_id"],
      "token" => tokens["refresh_token"],
      "token_type_hint" => "refresh_token"
    })

    assert info(ctx, tokens["access_token"]).status == 200
    assert exchange(ctx, %{refresh | "client_id" => client["client_id"]})["access_token"]
  end

  test "code replay revokes issued grants only with proof of the original verifier", ctx do
    {params, _, _, _, _} = grant(ctx)
    tokens = exchange(ctx, params)

    assert json_post(ctx, "/oauth/token", %{params | "code_verifier" => String.duplicate("z", 64)}).status ==
             400

    assert info(ctx, tokens["access_token"]).status == 200
    assert json_post(ctx, "/oauth/token", params).status == 400
    assert info(ctx, tokens["access_token"]).status == 401
  end

  test "deleted accounts cannot use or refresh existing grants", ctx do
    {params, client, _, email, _} = grant(ctx)
    tokens = exchange(ctx, params)
    Faro.Repo.get_by!(Faro.Accounts.User, email: email) |> Faro.Repo.delete!()
    assert info(ctx, tokens["access_token"]).status == 401

    assert json_post(ctx, "/oauth/token", %{
             "grant_type" => "refresh_token",
             "client_id" => client["client_id"],
             "refresh_token" => tokens["refresh_token"]
           }).status == 400
  end

  test "consent metadata is escaped and consent POST fields cannot change its recipient", ctx do
    {client, _} = register_client(ctx, %{"client_name" => "<script>alert(1)</script>"})
    {other, _} = register_client(ctx)
    {browser, _, _} = user(ctx)
    {params, verifier} = authorization(client)
    form = next(browser, ctx) |> get("/oauth/authorize", params)
    assert form.resp_body =~ "&lt;script&gt;"
    refute form.resp_body =~ "<script>"

    approved =
      next(form, ctx)
      |> post("/oauth/authorize", %{
        "decision" => "approve",
        "request_id" => request_id(form),
        "_csrf_token" => csrf(form),
        "client_id" => other["client_id"],
        "redirect_uri" => "https://attacker.example"
      })

    uri = approved |> redirected_to() |> URI.parse()
    assert uri.host == "127.0.0.1"
    code = URI.decode_query(uri.query)["code"]

    assert exchange(ctx, %{
             "grant_type" => "authorization_code",
             "client_id" => client["client_id"],
             "redirect_uri" => params["redirect_uri"],
             "code" => code,
             "code_verifier" => verifier
           })["access_token"]
  end

  test "invalid credentials stay generic and valid accounts can sign back in", ctx do
    {browser, email, password} = user(ctx)
    form = next(browser, ctx) |> get("/auth/login")
    next(form, ctx) |> post("/auth/logout", %{"_csrf_token" => csrf(form)})
    form = fresh(ctx) |> get("/auth/login")

    failed =
      next(form, ctx)
      |> post("/auth/login", %{
        "email" => email,
        "password" => "incorrect",
        "_csrf_token" => csrf(form)
      })

    assert failed.status == 422
    assert failed.resp_body =~ "Invalid email or password."

    signed_in =
      next(failed, ctx)
      |> post("/auth/login", %{
        "email" => email,
        "password" => password,
        "_csrf_token" => csrf(failed)
      })

    assert signed_in.status == 302
    {client, _} = register_client(ctx)
    {params, _} = authorization(client)
    assert next(signed_in, ctx) |> get("/oauth/authorize", params) |> Map.fetch!(:status) == 200
  end

  test "public client identifiers are canonicalized and alternate authentication cannot bypass replay policy",
       ctx do
    {params, client, _, _, _} = grant(ctx)
    tokens = exchange(ctx, %{params | "client_id" => String.upcase(client["client_id"])})

    refresh = %{
      "grant_type" => "refresh_token",
      "client_id" => client["client_id"],
      "refresh_token" => tokens["refresh_token"]
    }

    header = "Basic " <> Base.encode64(client["client_id"] <> ":not-a-secret")

    conn =
      fresh(ctx)
      |> put_req_header("authorization", header)
      |> put_req_header("content-type", "application/json")
      |> post("/oauth/token", Jason.encode!(refresh))

    assert conn.status == 401

    assert json_post(ctx, "/oauth/token", Map.put(refresh, "client_assertion", "not-supported")).status ==
             401

    rotated = exchange(ctx, refresh)

    assert json_post(ctx, "/oauth/revoke", %{
             "client_id" => String.upcase(client["client_id"]),
             "token" => tokens["refresh_token"],
             "token_type_hint" => "refresh_token"
           }).status == 200

    assert info(ctx, rotated["access_token"]).status == 401
  end

  test "Unicode passwords within the character policy are not silently truncated or byte-rejected",
       _ctx do
    password = String.duplicate("a\u0301\u0302\u0303", 100)
    assert byte_size(password) > 512
    email = Ecto.UUID.generate() <> "@example.test"
    assert {:ok, _} = Faro.Accounts.register(%{"email" => email, "password" => password})
    assert {:ok, _} = Faro.Accounts.authenticate(String.upcase(email), password)

    assert {:error, :invalid_credentials} =
             Faro.Accounts.authenticate(email, password <> "different")
  end

  test "malformed token requests and unsupported grants fail without issuing credentials", ctx do
    for params <- [
          %{},
          %{"grant_type" => "password"},
          %{"grant_type" => "client_credentials"},
          %{"grant_type" => ["authorization_code"]},
          %{"grant_type" => "authorization_code", "code_verifier" => []},
          %{"grant_type" => "refresh_token", "refresh_token" => [], "client_id" => %{}}
        ] do
      assert json_post(ctx, "/oauth/token", params).status in [400, 401]
    end

    assert Faro.Repo.aggregate(Boruta.Ecto.Token, :count) == 0
  end
end
