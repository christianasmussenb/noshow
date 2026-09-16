import json
import os
from contextlib import asynccontextmanager
from pathlib import Path

import anthropic
from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel

_BASE_DIR = Path(__file__).parent
load_dotenv(_BASE_DIR / ".env")

import iris_client
from system_prompt import SYSTEM_PROMPT
from tools import TOOLS

_ANTHROPIC_API_KEY = os.getenv("ANTHROPIC_API_KEY")
_anthropic = anthropic.AsyncAnthropic(api_key=_ANTHROPIC_API_KEY)
MODEL = "claude-sonnet-4-6"
MAX_TOOL_ROUNDS = 10


@asynccontextmanager
async def lifespan(app: FastAPI):
    yield


app = FastAPI(title="IRIS105 Chat", lifespan=lifespan)
app.mount("/static", StaticFiles(directory=str(_BASE_DIR / "static")), name="static")


class ChatRequest(BaseModel):
    message: str
    history: list[dict] = []


class ChatResponse(BaseModel):
    reply: str
    history: list[dict]


@app.get("/health")
async def health():
    return {"status": "ok", "model": MODEL}


@app.get("/")
async def index():
    return FileResponse(str(_BASE_DIR / "static" / "index.html"))


@app.post("/chat", response_model=ChatResponse)
async def chat(req: ChatRequest):
    if not _ANTHROPIC_API_KEY:
        raise HTTPException(
            status_code=503,
            detail="ANTHROPIC_API_KEY no está configurada. Define la variable de entorno "
            "para habilitar el chat.",
        )

    messages: list[dict] = req.history + [{"role": "user", "content": req.message}]

    for _ in range(MAX_TOOL_ROUNDS):
        response = await _anthropic.messages.create(
            model=MODEL,
            max_tokens=1024,
            system=SYSTEM_PROMPT,
            tools=TOOLS,
            messages=messages,
        )

        if response.stop_reason == "end_turn":
            reply = _extract_text(response)
            messages.append({"role": "assistant", "content": _serialize_content(response.content)})
            return ChatResponse(reply=reply, history=messages)

        if response.stop_reason == "tool_use":
            tool_results = []
            for block in response.content:
                if block.type == "tool_use":
                    try:
                        data = await iris_client.dispatch(block.name, block.input)
                    except Exception as exc:
                        data = {"error": str(exc)}
                    tool_results.append({
                        "type": "tool_result",
                        "tool_use_id": block.id,
                        "content": json.dumps(data, ensure_ascii=False),
                    })
            # pass raw SDK objects to the next API call, but store serializable version
            messages.append({"role": "assistant", "content": response.content})
            messages.append({"role": "user", "content": tool_results})
            continue

        # stop_reason inesperado — salir del loop
        break

    raise HTTPException(status_code=500, detail="No se pudo obtener respuesta tras múltiples rondas de tools.")


def _extract_text(response: anthropic.types.Message) -> str:
    for block in response.content:
        if hasattr(block, "text"):
            return block.text
    return ""


def _serialize_content(content) -> list[dict]:
    """Convert Anthropic SDK content blocks to plain dicts for JSON serialization."""
    result = []
    for block in content:
        if hasattr(block, "model_dump"):
            result.append(block.model_dump())
        elif isinstance(block, dict):
            result.append(block)
        else:
            result.append({"type": getattr(block, "type", "unknown"), "text": getattr(block, "text", "")})
    return result
