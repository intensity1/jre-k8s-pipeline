from flask import Flask, jsonify
import os

app = Flask(__name__)

# Baked in at build time by the Docker build (see Dockerfile ARG/ENV below)
# and by .github/workflows/build-push-app.yml, which passes the git SHA in.
# This makes it possible to look at a running pod and know EXACTLY which
# commit produced it, without needing to check Kubernetes annotations or
# CI logs - the running app tells you itself.
GIT_SHA = os.environ.get("GIT_SHA", "unknown")


@app.route("/")
def index():
    return jsonify(message="Hello from the homelab pipeline sample app", git_sha=GIT_SHA)


@app.route("/healthz")
def healthz():
    # Used by both the Kubernetes readiness AND liveness probes
    # (see infra/modules/k8s-app/main.tf)
    return jsonify(status="ok")


@app.route("/version")
def version():
    return jsonify(git_sha=GIT_SHA)


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
