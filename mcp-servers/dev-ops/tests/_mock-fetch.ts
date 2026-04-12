import { FetchImpl, FetchResponse } from "../src/client.js";

/**
 * In-memory fetch mock for dev-ops tests.
 *
 * Routes match on the literal `method path?search` pair (GET paths
 * match without the method prefix for convenience). Unmatched calls
 * return a 404 that echoes the URL so failures are easy to diagnose.
 */

export interface MockRoute {
  readonly body?: unknown;
  readonly rawBody?: string;
  readonly status?: number;
  readonly statusText?: string;
  readonly throwTransport?: boolean;
}

export interface MockFetch {
  readonly fetch: FetchImpl;
  readonly calls: Array<{ method: string; url: string; body?: string }>;
}

export function createMockFetch(
  routes: Record<string, MockRoute>,
): MockFetch {
  const calls: Array<{ method: string; url: string; body?: string }> = [];

  const fetchImpl: FetchImpl = async (input, init) => {
    const url = new URL(input);
    const method = init?.method ?? "GET";
    const key = `${method} ${url.pathname}${url.search}`;
    calls.push({ method, url: key, ...(init?.body !== undefined ? { body: init.body } : {}) });

    const route = routes[key] ?? routes[`${url.pathname}${url.search}`];
    if (!route) {
      return makeResponse(
        404,
        "Not Found",
        JSON.stringify({ url: key, message: "no mock route" }),
      );
    }
    if (route.throwTransport) {
      throw new Error("mock transport failure");
    }
    const body =
      route.rawBody ?? (route.body === undefined ? "" : JSON.stringify(route.body));
    return makeResponse(
      route.status ?? 200,
      route.statusText ?? "OK",
      body,
    );
  };

  return { fetch: fetchImpl, calls };
}

function makeResponse(
  status: number,
  statusText: string,
  body: string,
): FetchResponse {
  return {
    ok: status >= 200 && status < 300,
    status,
    statusText,
    text: async () => body,
  };
}
