from fastapi.testclient import TestClient

import app.main as main
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


def test_fault_injection_hits_api_not_health(monkeypatch):
    monkeypatch.setattr(main, "FAULT_RATE", 1.0)
    assert client.get("/api/agents").status_code == 503
    assert client.get("/healthz").status_code == 200
    body = client.get("/metrics").text
    # The 503 must carry the real route label, or the SLI (route=~"/api/.*") would miss it.
    assert 'route="/api/agents",status="503"' in body


def test_no_faults_by_default():
    assert main.FAULT_RATE == 0.0
    assert all(client.get("/api/agents").status_code == 200 for _ in range(20))
