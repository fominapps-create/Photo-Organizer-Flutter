from backend.model import load_model

m = load_model()
print('Model type:', type(m))
try:
    res = m('temp_test.png')[0]
    print('Boxes exist:', hasattr(res, 'boxes'))
    # Print number of boxes if available
    if hasattr(res, 'boxes') and res.boxes is not None:
        print('Num boxes:', len(res.boxes.conf))
    else:
        print('No boxes detected or boxes is None')
except Exception as e:
    print('Model run error:', type(e), e)
