import asyncio
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
    try:
        res = await backend_api.detect_tags(dummy)
        print('Returned:', res)
    except Exception as e:
        import traceback
        print('Exception in detect_tags:')
        traceback.print_exc()

if __name__ == '__main__':
    asyncio.run(run())
