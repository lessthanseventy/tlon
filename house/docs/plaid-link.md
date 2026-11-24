# Linking the bank again (Plaid)

The house reads the bank with an access token and never links it itself (`bank_plaid.gd` calls
only `/transactions/sync` and `/accounts/get`). The Plaid account allows **ten links for ever**, so
link once, only when the token is lost or revoked, and never to "see if it works".

The server's one-time link tool (`mix server.bank_link`, `Server.Home.Bank.Link`) was removed with the
server's home; its last source is in git at `f756203` (`server/lib/server/home/bank/link.ex`,
`plaid.ex`, `server/lib/mix/tasks/server.bank_link.ex`). What it did:

1. `POST https://production.plaid.com/link/token/create` with `client_id`, `secret`,
   `client_name`, `language: "en"`, `country_codes: ["US"]`, `user: {client_user_id}` and
   `products: ["transactions"]`; the answer holds `link_token`.
2. Served a page on `127.0.0.1` (a free port) that loads `https://cdn.plaid.com/link/v2/stable/link-initialize.js`,
   calls `Plaid.create({token: link_token, onSuccess})` from a button, and POSTs the `public_token`
   back to `/callback/<random nonce>` (compared in constant time, body at most 10 000 bytes). The
   login happens on the bank's own site.
3. `POST /item/public_token/exchange` with that `public_token`; the answer's `access_token` was
   printed once and kept nowhere.
4. The token goes to the machine's secrets (`plaid-access-token`, agenix in ficciones) and the house
   reads it from `PLAID_ACCESS_TOKEN` or `$XDG_RUNTIME_DIR/agenix/plaid-access-token`; the client id
   and secret are `PLAID_CLIENT_ID`/`PLAID_SECRET` or the secrets `plaid-client-id`, `plaid-secret`.

A run with a token already present was refused unless forced.
