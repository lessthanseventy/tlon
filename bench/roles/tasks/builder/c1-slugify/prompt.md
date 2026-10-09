Implement `Slug.slugify/1` in `lib/slug.ex` (it raises today). It turns a title into a URL slug:

- lowercase;
- accented Latin letters lose their accent first (`"Café Tlön"` → `"cafe-tlon"`);
- every run of characters that are not ASCII letters or digits becomes a single `-`;
- no leading or trailing `-`.

`"  Hello, World!  "` → `"hello-world"`, `"Orbis Tertius -- vol. 11"` → `"orbis-tertius-vol-11"`,
`"!!!"` → `""`.

The repo is plain Elixir scripts, no Mix project: `elixir test/slug_test.exs` runs its tests.
Work test-first, and commit when it is done.
