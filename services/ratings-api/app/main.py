import os
import random
import time

from fastapi import Depends, FastAPI, HTTPException, Request, Response
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Histogram, generate_latest

from app.data import AGENTS

VERSION = os.getenv("APP_VERSION", "dev")

# Fault injection for SLO drills: fraction (0.0-1.0) of /api requests answered with 503.
# Set through the Helm chart (values.yaml faultRate), so a drill is a Git commit like any other change.
FAULT_RATE = float(os.getenv("FAULT_RATE", "0"))

app = FastAPI(title="ratings-api", version=VERSION)

REQUESTS = Counter(
    "http_requests_total", "HTTP requests", ["method", "route", "status"]
)
LATENCY = Histogram(
    "http_request_duration_seconds", "HTTP request latency", ["method", "route"]
)


@app.middleware("http")
async def metrics_middleware(request: Request, call_next):
    start = time.perf_counter()
    response = await call_next(request)
    # Label by route template (/api/agents/{agent_id}), not raw path, to keep cardinality bounded.
    route = request.scope.get("route")
    path = getattr(route, "path", "unmatched")
    if path != "/metrics":
        REQUESTS.labels(request.method, path, str(response.status_code)).inc()
        LATENCY.labels(request.method, path).observe(time.perf_counter() - start)
    return response


def inject_fault():
    # Runs inside the matched route, so the 503 is labelled with the real route template
    # and counts against the SLI.
    if FAULT_RATE > 0 and random.random() < FAULT_RATE:
        raise HTTPException(status_code=503, detail="injected fault")


@app.get("/healthz")
def healthz():
    return {"status": "ok"}


@app.get("/api/version", dependencies=[Depends(inject_fault)])
def version():
    return {"version": VERSION}


@app.get("/api/agents", dependencies=[Depends(inject_fault)])
def list_agents():
    return AGENTS


@app.get("/api/agents/{agent_id}", dependencies=[Depends(inject_fault)])
def get_agent(agent_id: str):
    for agent in AGENTS:
        if agent["id"] == agent_id:
            return agent
    raise HTTPException(status_code=404, detail="agent not found")


# Prometheus scrape endpoint. Served on the pod port only; the HTTPRoute exposes /api/* and nothing else.
@app.get("/metrics", include_in_schema=False)
def metrics():
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)
