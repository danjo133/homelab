// OpenClaw plugin: SearXNG web search
// Provides a web_search tool backed by a self-hosted SearXNG instance.
const SEARXNG_URL = process.env.SEARXNG_URL || "http://searxng.open-webui.svc.cluster.local:8080";

module.exports = {
  id: "searxng-search",
  name: "SearXNG Search",
  description: "Web search via self-hosted SearXNG metasearch engine",
  register(api) {
    api.registerTool(
      {
        name: "web_search",
        label: "Web Search",
        description:
          "Search the web using SearXNG. Returns titles, URLs, and snippets from multiple search engines.",
        parameters: {
          type: "object",
          properties: {
            query: { type: "string", description: "Search query" },
            limit: { type: "number", description: "Max results to return (default 5)", default: 5 },
          },
          required: ["query"],
        },
        async execute(_id, params) {
          const query = params.query;
          const limit = params.limit || 5;

          const url = `${SEARXNG_URL}/search?q=${encodeURIComponent(query)}&format=json&count=${limit}`;
          const res = await fetch(url, {
            headers: { Accept: "application/json" },
          });

          if (!res.ok) {
            return [{ type: "text", text: `SearXNG error: ${res.status} ${res.statusText}` }];
          }

          const data = await res.json();
          const results = (data.results || []).slice(0, limit);

          if (results.length === 0) {
            return [{ type: "text", text: `No results found for: ${query}` }];
          }

          const formatted = results
            .map((r, i) => `${i + 1}. **${r.title}**\n   ${r.url}\n   ${r.content || ""}`)
            .join("\n\n");

          return [{ type: "text", text: formatted }];
        },
      },
      { names: ["web_search"] }
    );
  },
};
