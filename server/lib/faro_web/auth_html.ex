defmodule FaroWeb.AuthHTML do
  @moduledoc false
  import Plug.HTML, only: [html_escape: 1]

  def sign_in(csrf, error \\ nil) do
    message = if error, do: "<p role=\"alert\">#{html_escape(error)}</p>", else: ""

    page("Sign in to Faro", """
    #{message}
    <h2>Sign in</h2>
    <form method="post" action="/auth/login">
      <input type="hidden" name="_csrf_token" value="#{html_escape(csrf)}">
      <label>Email <input type="email" name="email" autocomplete="username" maxlength="254" required></label>
      <label>Password <input type="password" name="password" autocomplete="current-password" maxlength="128" required></label>
      <button type="submit">Sign in</button>
    </form>
    <h2>Create an account</h2>
    <p>Use a unique password of at least 15 characters. Email verification and password recovery are not available yet.</p>
    <form method="post" action="/auth/register">
      <input type="hidden" name="_csrf_token" value="#{html_escape(csrf)}">
      <label>Email <input type="email" name="email" autocomplete="username" maxlength="254" required></label>
      <label>Password <input type="password" name="password" autocomplete="new-password" minlength="15" maxlength="128" required></label>
      <button type="submit">Create account</button>
    </form>
    """)
  end

  def signed_in(csrf, user) do
    page("Signed in to Faro", """
    <p>You are signed in as <strong>#{html_escape(user.email)}</strong>.</p>
    <p>You can return to the application that requested access.</p>
    <form method="post" action="/auth/logout">
      <input type="hidden" name="_csrf_token" value="#{html_escape(csrf)}">
      <button type="submit">Sign out</button>
    </form>
    """)
  end

  def consent(csrf, user, client, scope, request_id) do
    page("Authorize a client", """
    <p>You are signed in as <strong>#{html_escape(user.email)}</strong>.</p>
    <p><strong>#{html_escape(client.name)}</strong> wants to access your Faro identity.</p>
    <p>This application name is supplied by its developer and is not verified by Faro.</p>
    <p>Requested permissions: <code>#{html_escape(scope)}</code>.</p>
    <p>Return address: <code>#{html_escape(client.redirect_uris |> Enum.join(", "))}</code></p>
    <form method="post" action="/oauth/authorize">
      <input type="hidden" name="_csrf_token" value="#{html_escape(csrf)}">
      <input type="hidden" name="request_id" value="#{html_escape(request_id)}">
      <button type="submit" name="decision" value="approve">Allow</button>
      <button type="submit" name="decision" value="deny">Deny</button>
    </form>
    <form method="post" action="/auth/logout">
      <input type="hidden" name="_csrf_token" value="#{html_escape(csrf)}">
      <button type="submit">Sign out</button>
    </form>
    """)
  end

  defp page(title, content),
    do: """
    <!doctype html><html lang="en"><head><meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1"><title>#{title} · Faro</title>
    <style>body{font:1rem/1.6 system-ui,sans-serif;max-width:36rem;margin:3rem auto;padding:0 1rem;color:#18243b;background:#f6f8fc}label{display:block;margin:1rem 0}input{display:block;padding:.6rem;max-width:90%;width:24rem}button{padding:.6rem 1rem;margin:.5rem .5rem .5rem 0}code{overflow-wrap:anywhere}[role=alert]{color:#a00}</style>
    </head><body><main><h1>#{title}</h1>#{content}</main></body></html>
    """
end
