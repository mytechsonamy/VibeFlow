import { FetchImpl, FetchResponse } from "../src/client.js";

/**
 * Minimal in-memory Figma fetch mock.
 *
 * Usage:
 *   const mock = createMockFetch({
 *     "/v1/files/abc/nodes?ids=1%3A2": { body: { nodes: { ... } } },
 *   });
 *   const client = new FigmaClient({ token: "x", fetchImpl: mock.fetch });
 *
 * Routes are matched by the request URL's pathname + search. Unmatched
 * routes return 404 with the URL echoed back so test failures are easy to
 * diagnose.
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
  readonly calls: string[];
}

export function createMockFetch(
  routes: Record<string, MockRoute>,
): MockFetch {
  const calls: string[] = [];

  const fetchImpl: FetchImpl = async (input) => {
    const url = new URL(input);
    const key = `${url.pathname}${url.search}`;
    calls.push(key);

    const route = routes[key];
    if (!route) {
      return makeResponse(404, "Not Found", JSON.stringify({ url: key, message: "no mock route" }));
    }

    if (route.throwTransport) {
      throw new Error("mock transport failure");
    }

    const body =
      route.rawBody ?? (route.body === undefined ? "" : JSON.stringify(route.body));
    return makeResponse(route.status ?? 200, route.statusText ?? "OK", body);
  };

  return { fetch: fetchImpl, calls };
}

function makeResponse(status: number, statusText: string, body: string): FetchResponse {
  return {
    ok: status >= 200 && status < 300,
    status,
    statusText,
    text: async () => body,
  };
}
