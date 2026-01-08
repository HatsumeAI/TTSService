import asyncio
import time
import os

from openai import AsyncOpenAI

openai = AsyncOpenAI(
    base_url="http://localhost:8080/v1",
    api_key="dummy-key"  # Local server doesn't need real key
)

async def main() -> None:
    script_dir = os.path.dirname(os.path.abspath(__file__))
    audio_path = os.path.join(script_dir, "../../Media/russian.wav")

    t0 = time.time()

    with open(audio_path, "rb") as f:
        translation = await openai.audio.translations.create(
            model="ru_RU",
            file=f,
        )

        print(translation.text)
        print(f"API took {time.time()-t0} seconds")

if __name__ == "__main__":
    asyncio.run(main())
