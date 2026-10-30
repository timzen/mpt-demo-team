# AGENTS.md — demo todo API

Conventions for anyone (human or AI teammate) changing this project. This is the
project's own knowledge: it lives here, beside the code it describes, so it's
versioned with it. (It used to be a my-pizza-team context-library entry,
`project-conventions`; MPT no longer keeps project knowledge — teammates read this
file because their prompt's Working Directory section tells them to.)

## Build and test

- `npm test` — Node's built-in test runner over `tests/*.test.ts` (no build step)
- `npm start` — run the server (`tsx src/index.ts`)

## Code Style
- Use TypeScript strict mode
- No external dependencies unless absolutely necessary
- Prefer Node.js built-ins (crypto, http, test runner)
- All files need a top-level JSDoc comment explaining purpose

## Testing
- Use Node's built-in test runner (`node --test`)
- Test files go in `tests/` with `.test.ts` suffix
- Each module should have corresponding tests

## API Design
- RESTful JSON endpoints
- Standard HTTP status codes (200, 201, 400, 401, 404)
- Error responses: `{ "error": "message" }`
