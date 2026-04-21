# Skill: add-endpoint

Adds a new REST endpoint to the backend AND a corresponding chart card to the frontend.

## When to use
When the user asks for "a new metric" or "a new chart" that needs end-to-end wiring.

## Steps
1. In the backend (`../entire-poc-backend`), create a new route under `src/api/routes/`.
2. Wire the route into `src/api/server.ts`.
3. In the frontend (`../entire-poc-frontend`), create a new chart component under `src/components/charts/`.
4. Add the new chart to `src/components/Dashboard.tsx`.
5. Run lint in both repos.
6. Commit each repo separately with a descriptive message.

## Reasoning notes
This skill deliberately spans both service repos so it produces multi-repo agent sessions for Pattern C testing.
