## On Enter
- Read the task description carefully
- Check existing code in `src/` to understand the current state
- Implement the required changes
- Run tests with `npm test` to verify nothing is broken
- When done:
  1. Create a diff: `git diff > /tmp/<TASKID>.diff`
  2. Upload the diff using `upload_attachment`
  3. Post a summary comment of what you accomplished
  4. Release the task (transitions to `review`)

## Exit Criteria
- Implementation complete
- Tests pass
- No linting errors
- Diff attached for lead review
