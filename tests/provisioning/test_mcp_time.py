import importlib.util
from datetime import datetime, timezone
from pathlib import Path
import unittest

from starlette.testclient import TestClient


SERVER_PATH = Path(__file__).resolve().parents[2] / "labautomation" / "mcp-time" / "server.py"
spec = importlib.util.spec_from_file_location("mcp_time_server", SERVER_PATH)
server = importlib.util.module_from_spec(spec)
spec.loader.exec_module(server)


class DateTimeMcpTests(unittest.TestCase):
    def test_streamable_http_discovery_and_current_utc_time(self):
        with TestClient(server.mcp.streamable_http_app()) as client:
            headers = {"Accept": "application/json, text/event-stream"}

            def rpc(request_id, method, params):
                response = client.post(
                    "/mcp",
                    headers=headers,
                    json={"jsonrpc": "2.0", "id": request_id, "method": method, "params": params},
                )
                self.assertEqual(response.status_code, 200, response.text)
                result = response.json()
                self.assertNotIn("error", result)
                return result["result"]

            initialized = rpc(1, "initialize", {
                "protocolVersion": "2025-06-18",
                "capabilities": {},
                "clientInfo": {"name": "bootcamp-tests", "version": "1.0"},
            })
            self.assertIn("tools", initialized["capabilities"])
            tools = rpc(2, "tools/list", {})["tools"]
            self.assertEqual(len(tools), 1)
            self.assertEqual(tools[0]["name"], "get_current_datetime")
            self.assertEqual(tools[0]["inputSchema"]["properties"], {})
            before = datetime.now(timezone.utc)
            result = rpc(3, "tools/call", {"name": "get_current_datetime", "arguments": {}})
            after = datetime.now(timezone.utc)
            self.assertFalse(result.get("isError", False))
            timestamp = datetime.fromisoformat(result["content"][0]["text"])
            self.assertEqual(timestamp.utcoffset().total_seconds(), 0)
            self.assertLessEqual(before, timestamp)
            self.assertLessEqual(timestamp, after)
            unknown = rpc(4, "tools/call", {"name": "not_a_tool", "arguments": {}})
            self.assertTrue(unknown["isError"])
            self.assertEqual(client.get("/healthz").text, "ok")


if __name__ == "__main__":
    unittest.main()
