import os
os.environ['KIVY_GL_BACKEND'] = 'angle_sdl2'
os.environ['KIVY_WINDOW'] = 'sdl2'
from ui.main_app_ui import PhotoOrganizerApp

if __name__ == "__main__":
    PhotoOrganizerApp().run()
