/**
 * tests/todos.test.ts — Basic tests for the todo API.
 *
 * Uses Node's built-in test runner.
 */

import { describe, it, beforeEach } from "node:test";
import assert from "node:assert/strict";
import { todos } from "../src/index.ts";

// Simple test helper to make requests to the handler
// (In a real setup you'd use supertest or similar)

describe("Todo API", () => {
  beforeEach(() => {
    todos.clear();
  });

  it("should start with no todos", () => {
    assert.equal(todos.size, 0);
  });

  it("should store a todo in the map", () => {
    todos.set("1", { id: "1", title: "Test todo", done: false });
    assert.equal(todos.size, 1);
    assert.equal(todos.get("1")?.title, "Test todo");
  });

  it("should toggle done status", () => {
    todos.set("1", { id: "1", title: "Test", done: false });
    const todo = todos.get("1")!;
    todo.done = !todo.done;
    assert.equal(todo.done, true);
  });

  it("should delete a todo", () => {
    todos.set("1", { id: "1", title: "Test", done: false });
    todos.delete("1");
    assert.equal(todos.size, 0);
  });
});
