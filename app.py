# -*- coding: utf-8 -*-
import gevent.monkey

gevent.monkey.patch_all()

import flask


app = flask.Flask(__name__)

@app.route('/helloworld', methods={'GET'}, endpoint='helloworld')
def helloworld():
    return flask.Response('hello world')
