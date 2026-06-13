# Project Conventions

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
