/**
 * src/index.ts — Entry point for the demo todo API.
 *
 * A minimal HTTP server with in-memory todo storage.
 * No authentication yet (that's what the story tasks will add).
 */

import { createServer, IncomingMessage, ServerResponse } from "node:http";

export interface Todo {
  id: string;
  title: string;
  done: boolean;
}

const todos: Map<string, Todo> = new Map();
let nextId = 1;

/** Parse JSON body from request */
function parseBody(req: IncomingMessage): Promise<unknown> {
  return new Promise((resolve, reject) => {
    const chunks: Buffer[] = [];
    req.on("data", (chunk) => chunks.push(chunk));
    req.on("end", () => {
      try {
        resolve(JSON.parse(Buffer.concat(chunks).toString()));
      } catch {
        resolve(null);
      }
    });
    req.on("error", reject);
  });
}

/** Send JSON response */
function json(res: ServerResponse, status: number, data: unknown) {
  res.writeHead(status, { "Content-Type": "application/json" });
  res.end(JSON.stringify(data));
}

/** Request handler */
async function handler(req: IncomingMessage, res: ServerResponse) {
  const url = new URL(req.url || "/", `http://${req.headers.host}`);
  const method = req.method || "GET";

  // GET /todos — list all todos
  if (method === "GET" && url.pathname === "/todos") {
    return json(res, 200, [...todos.values()]);
  }

  // POST /todos — create a todo
  if (method === "POST" && url.pathname === "/todos") {
    const body = (await parseBody(req)) as { title?: string } | null;
    if (!body?.title) {
      return json(res, 400, { error: "title is required" });
    }
    const todo: Todo = { id: String(nextId++), title: body.title, done: false };
    todos.set(todo.id, todo);
    return json(res, 201, todo);
  }

  // PATCH /todos/:id — toggle done
  if (method === "PATCH" && url.pathname.startsWith("/todos/")) {
    const id = url.pathname.split("/")[2];
    const todo = todos.get(id);
    if (!todo) return json(res, 404, { error: "not found" });
    todo.done = !todo.done;
    return json(res, 200, todo);
  }

  // DELETE /todos/:id
  if (method === "DELETE" && url.pathname.startsWith("/todos/")) {
    const id = url.pathname.split("/")[2];
    if (!todos.delete(id)) return json(res, 404, { error: "not found" });
    return json(res, 204, null);
  }

  json(res, 404, { error: "not found" });
}

const PORT = Number(process.env.PORT) || 3456;
const server = createServer(handler);

server.listen(PORT, () => {
  console.log(`Demo Todo API running on http://localhost:${PORT}`);
});

export { server, todos, handler };
