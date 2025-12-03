import asyncio, time
from backend import backend_api

class DummyUploadFile:
    def __init__(self, filename, path):
        self.filename = filename
        self._path = path
    async def read(self):
        with open(self._path, 'rb') as f:
            return f.read()

async def run():
    dummy = DummyUploadFile('folder.png', 'assets/icons/folder.png')
    t0 = time.time()
    res = await backend_api.detect_tags(dummy)
    t1 = time.time()
    print('Returned:', res)
    print('Total detect_tags call time:', round((t1 - t0), 3), 's')

if __name__ == '__main__':
    asyncio.run(run())
