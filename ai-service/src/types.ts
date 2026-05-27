export interface AppContext {
  bundleId: string;
  name: string;
}

export interface SelectionRange {
  location: number;
  length: number;
}

export interface CompleteRequest {
  requestId: string;
  context: string;
  app: AppContext;
  selection?: SelectionRange;
}

export interface CompleteResponse {
  requestId: string;
  completion: string;
  model: string;
  latencyMs: number;
}

export type LearnEvent = "accepted" | "rejected" | "curated";

export interface LearnRequest {
  requestId: string;
  event: LearnEvent;
  contextHash: string;
  suggestion: string;
  app: AppContext;
}

export interface Profile {
  name: string;
  role: string;
  projects: string[];
  vocabulary: string[];
  tone: string;
  languages: string[];
  peopleOrgs: string[];
  neverSay: string[];
}

export interface LearnedExample {
  text: string;
  source: "accepted" | "curated";
  appName?: string;
}
