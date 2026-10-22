"""Émet une petite trace de deux services, avec propagation W3C par HTTP (M23-E24).

Un « client » (service capot-client) appelle un « serveur » local (service capot-serveur, dans un fil) :
le client injecte le contexte dans les en-têtes HTTP, le serveur l'extrait et crée sa span enfant.
Chaque côté a son propre fournisseur de traces, comme deux applications distinctes.

    admin@adm01:~/m23/e24$ uv run --with opentelemetry-sdk==1.45.1 \
        --with opentelemetry-exporter-otlp-proto-http==1.45.1 python emettre.py

Exporte en OTLP/HTTP (protobuf) vers le Collector local (127.0.0.1:24318) et affiche les en-têtes reçus.
"""

from __future__ import annotations

import threading
import urllib.request
from http.server import BaseHTTPRequestHandler, HTTPServer

from opentelemetry import propagate, trace
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor

POINT = "http://127.0.0.1:24318/v1/traces"


def fournisseur(nom: str) -> TracerProvider:
    f = TracerProvider(
        resource=Resource.create({"service.name": nom, "deployment.environment.name": "essai"})
    )
    f.add_span_processor(BatchSpanProcessor(OTLPSpanExporter(endpoint=POINT)))
    return f


CLIENT = fournisseur("capot-client")
SERVEUR = fournisseur("capot-serveur")


class Gestionnaire(BaseHTTPRequestHandler):
    def do_GET(self) -> None:
        recus = {
            k: v
            for k, v in self.headers.items()
            if k.lower() in ("traceparent", "tracestate", "baggage")
        }
        print("en-têtes reçus par le serveur :", recus)
        # Les noms d'en-têtes HTTP ne sont pas sensibles à la casse, mais le lecteur par défaut d'un dict, si :
        # sans passage en minuscules, « Traceparent » ne serait pas trouvé et le serveur ouvrirait une NOUVELLE trace.
        contexte = propagate.extract({k.lower(): v for k, v in self.headers.items()})
        with SERVEUR.get_tracer("capot").start_as_current_span(
            "GET /capot", context=contexte, kind=trace.SpanKind.SERVER
        ) as span:
            span.set_attribute("http.route", "/capot")
            span.set_attribute("http.response.status_code", 200)
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"ok")

    def log_message(self, *args: object) -> None:  # pas de journal d'accès sur stderr
        pass


def main() -> None:
    serveur = HTTPServer(("127.0.0.1", 0), Gestionnaire)
    threading.Thread(target=serveur.serve_forever, daemon=True).start()
    url = f"http://127.0.0.1:{serveur.server_port}/capot"

    traceur = CLIENT.get_tracer("capot")
    with traceur.start_as_current_span("traitement", kind=trace.SpanKind.INTERNAL) as racine:
        racine.set_attribute("workbook.exercice", "M23-E24")
        with traceur.start_as_current_span("GET", kind=trace.SpanKind.CLIENT) as appel:
            appel.set_attribute("url.full", url)
            entetes: dict[str, str] = {}
            propagate.inject(entetes)  # tracecontext + baggage par défaut (OTEL_PROPAGATORS)
            print("en-têtes injectés par le client :", entetes)
            with urllib.request.urlopen(
                urllib.request.Request(url, headers=entetes), timeout=5
            ) as rep:
                appel.set_attribute("http.response.status_code", rep.status)
        ctx = racine.get_span_context()
        print(
            f"trace_id={ctx.trace_id:032x} span_id(racine)={ctx.span_id:016x} drapeaux={int(ctx.trace_flags):02x}"
        )

    serveur.shutdown()
    CLIENT.shutdown()  # vide les lots avant de quitter
    SERVEUR.shutdown()


if __name__ == "__main__":
    main()
