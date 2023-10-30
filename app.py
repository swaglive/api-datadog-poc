# -*- coding: utf-8 -*-
'''
 ___ _ _ _ ___ ___
|_ -| | | | .'| . |
|___|_____|__,|_  |
              |___|
'''
import gevent.monkey; gevent.monkey.patch_all()
import flask


app = flask.Flask(__name__)
app.register_blueprint(flask.Blueprint('swag', __name__))

@app.route('/helloworld', methods={'GET'}, endpoint='helloworld')
def helloworld():
    return flask.Response('hello world')
