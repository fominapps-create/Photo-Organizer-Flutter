from backend import backend_api
from fastapi.routing import APIRoute

for r in backend_api.app.routes:
    if isinstance(r, APIRoute):
        print('Path:', r.path)
        print('Name:', r.name)
        print('Methods:', r.methods)
        print('Dependants:', r.dependant)
        print('Body field params:', [p.name for p in r.dependant.request_params])
        print('---')
