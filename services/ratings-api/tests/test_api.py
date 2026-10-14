from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_healthz():
    r = client.get("/healthz")
    assert r.status_code == 200
    assert r.json() == {"status": "ok"}


def test_list_agents():
    r = client.get("/api/agents")
    assert r.status_code == 200
    agents = r.json()
    assert len(agents) >= 3
    for a in agents:
        assert 0 <= a["critics_score"] <= 100
        assert 0 <= a["audience_score"] <= 100


def test_get_agent_found_and_missing():
    assert client.get("/api/agents/sample-receptionist-a").status_code == 200
    assert client.get("/api/agents/does-not-exist").status_code == 404


def test_metrics_use_route_template_not_raw_path():
    client.get("/api/agents/sample-receptionist-b")
    body = client.get("/metrics").text
    assert 'route="/api/agents/{agent_id}"' in body
    assert "sample-receptionist-b" not in body
