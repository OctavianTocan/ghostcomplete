import fs from "node:fs";
import path from "node:path";
import { Database } from "bun:sqlite";
import type { AppContext, LearnedExample, LearnRequest } from "./types.js";

export class LearningStore {
  private db: Database;

  constructor(databasePath: string) {
    fs.mkdirSync(path.dirname(databasePath), { recursive: true });
    this.db = new Database(databasePath);
    this.db.exec(`
      PRAGMA journal_mode = WAL;
      CREATE TABLE IF NOT EXISTS profile_facts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        key TEXT NOT NULL,
        value TEXT NOT NULL,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
      );
      CREATE TABLE IF NOT EXISTS suggestion_events (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        request_id TEXT NOT NULL,
        event TEXT NOT NULL,
        context_hash TEXT NOT NULL,
        suggestion TEXT,
        app_bundle_id TEXT NOT NULL,
        app_name TEXT NOT NULL,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
      );
      CREATE TABLE IF NOT EXISTS curated_snippets (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        text TEXT NOT NULL,
        app_bundle_id TEXT,
        app_name TEXT,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
      );
      CREATE TABLE IF NOT EXISTS embeddings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        snippet_id INTEGER NOT NULL,
        provider TEXT NOT NULL,
        model TEXT NOT NULL,
        vector_json TEXT NOT NULL,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
      );
      CREATE TABLE IF NOT EXISTS settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL,
        updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
      );
    `);
  }

  recordCompletionRequest(requestId: string, contextHash: string, app: AppContext): void {
    this.db
      .prepare(
        `INSERT INTO suggestion_events (request_id, event, context_hash, suggestion, app_bundle_id, app_name)
         VALUES (?, 'requested', ?, NULL, ?, ?)`,
      )
      .run(requestId, contextHash, app.bundleId, app.name);
  }

  recordLearnEvent(event: LearnRequest): void {
    this.db
      .prepare(
        `INSERT INTO suggestion_events (request_id, event, context_hash, suggestion, app_bundle_id, app_name)
         VALUES (?, ?, ?, ?, ?, ?)`,
      )
      .run(event.requestId, event.event, event.contextHash, event.suggestion, event.app.bundleId, event.app.name);

    if (event.event === "curated" && event.suggestion.trim()) {
      this.db
        .prepare(`INSERT INTO curated_snippets (text, app_bundle_id, app_name) VALUES (?, ?, ?)`)
        .run(event.suggestion, event.app.bundleId, event.app.name);
    }
  }

  getExamples(app: AppContext, limit = 6): LearnedExample[] {
    const rows = this.db
      .prepare(
        `SELECT suggestion AS text, 'accepted' AS source, app_name AS appName
           FROM suggestion_events
          WHERE event = 'accepted'
            AND suggestion IS NOT NULL
            AND length(trim(suggestion)) > 0
            AND (app_bundle_id = ? OR app_name = ?)
          ORDER BY created_at DESC
          LIMIT ?`,
      )
      .all(app.bundleId, app.name, limit) as Array<{ text: string; source: "accepted"; appName: string }>;

    if (rows.length >= limit) return rows;

    const curated = this.db
      .prepare(
        `SELECT text, 'curated' AS source, app_name AS appName
           FROM curated_snippets
          ORDER BY created_at DESC
          LIMIT ?`,
      )
      .all(limit - rows.length) as Array<{ text: string; source: "curated"; appName?: string }>;

    return [...rows, ...curated];
  }

  close(): void {
    this.db.close();
  }
}
