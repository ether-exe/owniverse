# Owniverse

Write a page. Decide what a stranger reads.

Owniverse is a Flutter web app with a Notion-style block canvas and one idea a
block editor does not normally have: **a door**. Everything after it needs an
identity, and the gated part is never sent to a reader who has not entered — not
hidden with CSS, absent from the payload.

> Status: early. The database exists and is tested; the interface is being built.

## How it works

- A **Space** is one page, written from blocks.
- Publishing freezes a snapshot at `@username/slug`. Later edits stay drafts
  until you publish again, so a live URL never changes under a reader.
- The `door` block splits the document. Publishing writes three snapshots — the
  full document for the owner, the public slice, and the gated slice — and the
  public one is the only thing an anonymous client can be served.
- Readers and likes only exist past a door, because a counter without an
  identity counts page loads, not people.

## Running it

```bash
cp dart_define.example.json dart_define.json   # then fill in your project
flutter pub get
flutter run -d chrome --dart-define-from-file=dart_define.json
```

`dart_define.json` is gitignored — it holds the project address and the
**publishable** key, which is safe in a browser bundle because that is what a
browser gets anyway. The secret/service key must never go in it.

## Backend

Schema, row level security, functions and storage policies live in
`supabase/migrations/`, applied with the [Supabase CLI](https://supabase.com/docs/guides/cli):

```bash
npx supabase link --project-ref <ref>
npx supabase db push
```

The security suite runs against the linked project and asserts what an attacker
actually receives:

```bash
SUPABASE_URL=… SUPABASE_PUBLISHABLE_KEY=… \
SUPABASE_ACCESS_TOKEN=… SUPABASE_PROJECT_REF=… \
node scripts/db-test.mjs
```

It creates its own users and deletes them afterwards.

## Checks

```bash
flutter analyze
flutter test
flutter build web --release
```
