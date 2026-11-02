//@component
// CustomHint.js
// Version: 1.0.0
// Event: On Awake
// Description: Provides controls for setting up different kings of hints in the lens
// 
// public api: 
// Show hint from another script
// script.showHint()
// 
// Hide hint from another script
// script.hideHint()

//@input string hintType = "image" {"label" : "Type" ,"widget":"combobox", "values":[{"label":"Text", "value":"text"}, {"label":"Image", "value":"image"}, {"label":"Mesh", "value":"mesh"}]}
//@input Component.Text text {"showIf":"hintType", "showIfValue":"text"}
//@input Component.Image image {"showIf":"hintType", "showIfValue":"image"}
//@input Component.RenderMeshVisual mesh {"showIf":"hintType", "showIfValue":"mesh"}
//@ui {"widget":"separator"}
//@input int camera {"label" : "Show Hint", "widget":"combobox", "values":[{"label" : "On Front Camera","value":"0"},{"label" : "On Back Camera","value":"1"}, {"label" : "On Both Cameras","value":"2"}, {"label" : "On None","value":"3"}]}
//@ui {"widget":"label", "label":"Use public script api to control hint:<br>script.showHint<br> script.hideHint", "showIf" : "camera", "showIfValue" : "3"}
//@ui {"widget":"separator"}
//@ui {"widget":"group_start","label":"Duration"}
//@input float appearDelay = 0.0 {"label" : "Delay", "min" : 0, "hint" : "Delay before hint is shown"}
//@input float appearDuration = 0.8 {"label" : "Fade In", "min" : 0, "hint" : "Hint fade-in time"}
//@input float screenDuration = 2.0 {"label" : "Shown Time", "min" : 0, "hint" : "How long hint stays on screen"}
//@input float disappearDuration = 0.8 {"label" : "Fade Out", "min" : 0, "hint" : "Hint fade-out time"}
//@input int repeatCount = 3 {"label":"Animation Loops", "hint": "Animated texture loop count, -1 to loop infinitely"} 
//@ui {"widget":"group_end"}
//@ui {"widget":"separator"}
//@input bool advanced = false
//@ui {"widget":"group_start","label":"Duration", "showIf" : "advanced"}
//@input bool tweenPrintDebugLog = false  {"label" : "Tween Logs"}
//@input bool disableHiding = false {"label" : "Disable Hiding"}
//@input bool showOnce = false  {"label" : "Show Once"}
//@input bool hideIfCapture = true {"label" : "Hide On Capture"}
//@input bool hideOnCamSwitch = true {"label" : "Hide On Camera Switch"}
//@ui {"widget":"group_end"}
/* eslint-disable */
function main() {
    if (!global.CustomHint) {
        initializeCustomHint();
    }
    var component = null;
    switch (script.hintType) {
        case "text": {
            component = script.text;
        } break;
        case "image": {
            component = script.image;
        } break;
        case "mesh": {
            component = script.mesh;
        } break;
    }
    if (!component) {
        print("Error, " + script.hintType + " component not specified");
    } else {
        var hint = new global.CustomHint(component,
            script.appearDuration * 1000,
            script.disappearDuration * 1000,
            script.screenDuration,
            script.appearDelay * 1000,
            script.repeatCount,
            !script.disableHiding,
            script.hideIfCapture,
            script.hintType);

        var frontCameraEvent = script.createEvent("SceneEvent.CameraFrontEvent");
        var backCameraEvent = script.createEvent("SceneEvent.CameraBackEvent");


        switch (script.camera) {
            case 3:
                // call from script instead
                hint.forceHide();
                break;
            case 0:
                frontCameraEvent.bind(showHint);
                if (script.hideOnCamSwitch) {
                    backCameraEvent.bind(hideHint);
                }
                break;
            case 1:
                backCameraEvent.bind(showHint);
                if (script.hideOnCamSwitch) {
                    frontCameraEvent.bind(hideHint);
                }
                break;
            case 2:
                frontCameraEvent.bind(showHint);
                backCameraEvent.bind(showHint);
                break;
        }

        // ------------------------------

        function showHint() {
            if (script.showOnce && hint.showCount > 0) {
                return;
            }
            hint.show();
        }

        function hideHint() {
            hint.forceHide();
        }

        script.showHint = showHint;
        script.hideHint = hideHint;
    }
}

main();


function initializeCustomHint() {
    function CustomHint(component, appearDuration, disappearDuration, onScreenDuration, appearDelay, repeatCount, showHide, hideIfCapture, mode) {
        this.component = component;
        this.appearDuration = appearDuration;
        this.disappearDuration = disappearDuration;
        this.onScreenDuration = onScreenDuration;
        this.appearDelay = appearDelay;
        this.repeatCount = repeatCount;
        this.showHide = showHide;
        this.mode = mode;
        this.getInitialInformation();
        this.setAlpha(0.0);
        this.showCount = 0;
        this.interrupt = false;
        if (hideIfCapture) {
            this.forceStopIfCapture();
        }
        if (this.showHide) {
            this.createCallbackForHide();
        }
        this.CreateCallbackForTextureAnimation();
    }

    CustomHint.prototype.getInitialInformation = function () {
        if (this.mode == "text") {
            this.pass = {
                "text": this.component.textFill,
                "outline": this.component.outlineSettings.fill,
                "dropshadow": this.component.dropshadowSettings.fill,
                "background": this.component.backgroundSettings.fill
            };
            this.color = {
                "text": this.pass["text"].color,
                "outline": this.pass["outline"].color,
                "dropshadow": this.pass["dropshadow"].color,
                "background": this.pass["background"].color
            };
            this.initAlpha = {
                "text": this.color["text"].a,
                "outline": this.color["outline"].a,
                "dropshadow": this.color["dropshadow"].a,
                "background": this.color["background"].a
            };
        }
        if (this.mode == "image" || this.mode == "mesh") {
            this.pass = this.component.mainPass;
            this.baseColor = this.pass.baseColor;
            this.initAlpha = this.baseColor.a;
        }

    };

    CustomHint.prototype.createCallbackForHide = function () {
        var obj = this;
        this.delayedHide = script.createEvent("SceneEvent.DelayedCallbackEvent");
        this.delayedHide.bind(function () {
            obj.hide();
        });
    };

    CustomHint.prototype.CreateCallbackForTextureAnimation = function () {
        var obj = this;
        this.delayedTextureAnimation = script.createEvent("SceneEvent.DelayedCallbackEvent");
        this.delayedTextureAnimation.bind(function () {
            if (obj.mode == "image" || obj.mode == "mesh") {
                var provider = obj.pass.baseTex.control;
                if (provider.isOfType("Provider.AnimatedTextureFileProvider")) {
                    provider.play(obj.repeatCount, 0);
                }
            }
        });
    };

    CustomHint.prototype.setAlpha = function (val) {
        if (this.mode == "text") {
            this.color["text"].a = this.initAlpha["text"] * val;
            this.color["outline"].a = this.initAlpha["outline"] * val;
            this.color["dropshadow"].a = this.initAlpha["dropshadow"] * val;
            this.color["background"].a = this.initAlpha["background"] * val;

            this.pass["text"].color = this.color["text"];
            this.pass["outline"].color = this.color["outline"];
            this.pass["dropshadow"].color = this.color["dropshadow"];
            this.pass["background"].color = this.color["background"];
        }
        if (this.mode == "image" || this.mode == "mesh") {
            this.baseColor.a = this.initAlpha * val;
            this.pass.baseColor = this.baseColor;
        }

    };

    CustomHint.prototype.show = function () {
        this.interrupt = false;
        this.showCount++;
        var obj = this;
        if (!this.component.enabled) {
            this.setAlpha(0.0);
            this.component.enabled = true;
        }

        if (obj.mode == "image" || obj.mode == "mesh") {
            var provider = obj.pass.baseTex.control;
            if (provider.isOfType("Provider.AnimatedTextureFileProvider")) {
                provider.pauseAtFrame(0);
            }
        }
        obj.delayedTextureAnimation.reset(obj.appearDelay / 1000.0);

        this.showTween = new TWEEN.Tween({ x: 0.0 })
            .to({ x: 1.0 }, obj.appearDuration)
            .easing(TWEEN.Easing.Sinusoidal.In)
            .onUpdate(function (val) {
                obj.setAlpha(val.x);
            })
            .onComplete(function () {
                if (obj.showHide) {
                    obj.delayedHide.reset(obj.onScreenDuration);
                }
            }.bind(this))
            .delay(obj.appearDelay)
            .start();
    };

    CustomHint.prototype.hide = function () {
        if (this.interrupt) {
            return;
        }
        var obj = this;
        this.hideTween = new TWEEN.Tween({ x: 1.0 })
            .to({ x: 0.0 }, this.disappearDuration)
            .easing(TWEEN.Easing.Sinusoidal.Out)
            .onUpdate(function (val) {
                obj.setAlpha(val.x);
            })
            .start();
    };

    CustomHint.prototype.forceStopIfCapture = function () {
        this.capture = script.createEvent("SceneEvent.SnapImageCaptureEvent");
        this.record = script.createEvent("SceneEvent.SnapRecordStartEvent");
        this.capture.bind(this.forceHide.bind(this));
        this.record.bind(this.forceHide.bind(this));
    };

    CustomHint.prototype.forceHide = function () {
        this.interrupt = true;
        this.component.enabled = false;
        if (this.showTween) {
            this.showTween.stop();
        }
        if (this.hideTween) {
            this.hideTween.stop();
        }
        this.setAlpha(0.0);
    };

    global.CustomHint = CustomHint;
}

/// ========================= Tween.js =====================================

var _Group = function () {
    this._tweens = {};
    this._tweensAddedDuringUpdate = {};
};

_Group.prototype = {
    getAll: function () {

        return Object.keys(this._tweens).map(function (tweenId) {
            return this._tweens[tweenId];
        }.bind(this));

    },

    removeAll: function () {

        this._tweens = {};

    },

    add: function (tween) {

        this._tweens[tween.getId()] = tween;
        this._tweensAddedDuringUpdate[tween.getId()] = tween;

    },

    remove: function (tween) {

        delete this._tweens[tween.getId()];
        delete this._tweensAddedDuringUpdate[tween.getId()];

    },

    update: function (time, preserve) {

        var tweenIds = Object.keys(this._tweens);

        if (tweenIds.length === 0) {
            return false;
        }

        time = time !== undefined ? time : TWEEN.now();

        // Tweens are updated in "batches". If you add a new tween during an update, then the
        // new tween will be updated in the next batch.
        // If you remove a tween during an update, it may or may not be updated. However,
        // if the removed tween was added during the current batch, then it will not be updated.
        while (tweenIds.length > 0) {
            this._tweensAddedDuringUpdate = {};

            for (var i = 0; i < tweenIds.length; i++) {

                var tween = this._tweens[tweenIds[i]];

                if (tween && tween.update(time) === false) {
                    tween._isPlaying = false;

                    if (!preserve) {
                        delete this._tweens[tweenIds[i]];
                    }
                }
            }

            tweenIds = Object.keys(this._tweensAddedDuringUpdate);
        }

        return true;

    }
};

var TWEEN = new _Group();

TWEEN.Group = _Group;
TWEEN._nextId = 0;
TWEEN.nextId = function () {
    return TWEEN._nextId++;
};


// Include a performance.now polyfill.
// In node.js, use process.hrtime.
if (typeof (window) === "undefined" && typeof (process) !== "undefined") {
    TWEEN.now = function () {
        var time = process.hrtime();

        // Convert [seconds, nanoseconds] to milliseconds.
        return time[0] * 1000 + time[1] / 1000000;
    };
}
// In a browser, use window.performance.now if it is available.
else if (typeof (window) !== "undefined" &&
    window.performance !== undefined &&
    window.performance.now !== undefined) {
    // This must be bound, because directly assigning this function
    // leads to an invocation exception in Chrome.
    TWEEN.now = window.performance.now.bind(window.performance);
}
// Use Date.now if it is available.
else if (Date.now !== undefined) {
    TWEEN.now = Date.now;
}
// Otherwise, use 'new Date().getTime()'.
else {
    TWEEN.now = function () {
        return new Date().getTime();
    };
}


TWEEN.Tween = function (object, group) {
    this._object = object;
    this._valuesStart = {};
    this._valuesEnd = {};
    this._valuesStartRepeat = {};
    this._duration = 1000;
    this._repeat = 0;
    this._repeatDelayTime = undefined;
    this._yoyo = false;
    this._isPlaying = false;
    this._reversed = false;
    this._delayTime = 0;
    this._startTime = null;
    this._easingFunction = TWEEN.Easing.Linear.None;
    this._interpolationFunction = TWEEN.Interpolation.Linear;
    this._chainedTweens = [];
    this._onStartCallback = null;
    this._onStartCallbackFired = false;
    this._onUpdateCallback = null;
    this._onCompleteCallback = null;
    this._onStopCallback = null;
    this._group = group || TWEEN;
    this._id = TWEEN.nextId();

};

TWEEN.Tween.prototype = {
    getId: function getId() {
        return this._id;
    },

    isPlaying: function isPlaying() {
        return this._isPlaying;
    },

    to: function to(properties, duration) {

        this._valuesEnd = properties;

        if (duration !== undefined) {
            this._duration = duration;
        }

        return this;

    },

    start: function start(time) {

        this._group.add(this);

        this._isPlaying = true;

        this._onStartCallbackFired = false;

        this._startTime = time !== undefined ? typeof time === "string" ? TWEEN.now() + parseFloat(time) : time : TWEEN.now();
        this._startTime += this._delayTime;

        for (var property in this._valuesEnd) {

            // Check if an Array was provided as property value
            if (this._valuesEnd[property] instanceof Array) {

                if (this._valuesEnd[property].length === 0) {
                    continue;
                }

                // Create a local copy of the Array with the start value at the front
                this._valuesEnd[property] = [this._object[property]].concat(this._valuesEnd[property]);

            }

            // If `to()` specifies a property that doesn't exist in the source object,
            // we should not set that property in the object
            if (this._object[property] === undefined) {
                continue;
            }

            // Save the starting value.
            this._valuesStart[property] = this._object[property];

            if ((this._valuesStart[property] instanceof Array) === false) {
                this._valuesStart[property] *= 1.0; // Ensures we're using numbers, not strings
            }

            this._valuesStartRepeat[property] = this._valuesStart[property] || 0;

        }

        return this;

    },

    stop: function stop() {

        if (!this._isPlaying) {
            return this;
        }

        this._group.remove(this);
        this._isPlaying = false;

        if (this._onStopCallback !== null) {
            this._onStopCallback(this._object);
        }

        this.stopChainedTweens();
        return this;

    },

    end: function end() {

        this.update(this._startTime + this._duration);
        return this;

    },

    stopChainedTweens: function stopChainedTweens() {

        for (var i = 0, numChainedTweens = this._chainedTweens.length; i < numChainedTweens; i++) {
            this._chainedTweens[i].stop();
        }

    },

    delay: function delay(amount) {

        this._delayTime = amount;
        return this;

    },

    repeat: function repeat(times) {

        this._repeat = times;
        return this;

    },

    repeatDelay: function repeatDelay(amount) {

        this._repeatDelayTime = amount;
        return this;

    },

    yoyo: function yoyo(yoyo) {

        this._yoyo = yoyo;
        return this;

    },

    easing: function easing(easing) {

        this._easingFunction = easing;
        return this;

    },

    interpolation: function interpolation(interpolation) {

        this._interpolationFunction = interpolation;
        return this;

    },

    chain: function chain() {

        this._chainedTweens = arguments;
        return this;

    },

    onStart: function onStart(callback) {

        this._onStartCallback = callback;
        return this;

    },

    onUpdate: function onUpdate(callback) {

        this._onUpdateCallback = callback;
        return this;

    },

    onComplete: function onComplete(callback) {

        this._onCompleteCallback = callback;
        return this;

    },

    onStop: function onStop(callback) {

        this._onStopCallback = callback;
        return this;

    },

    update: function update(time) {

        var property;
        var elapsed;
        var value;

        if (time < this._startTime) {
            return true;
        }

        if (this._onStartCallbackFired === false) {

            if (this._onStartCallback !== null) {
                this._onStartCallback(this._object);
            }

            this._onStartCallbackFired = true;
        }

        elapsed = (time - this._startTime) / this._duration;
        elapsed = elapsed > 1 ? 1 : elapsed;

        value = this._easingFunction(elapsed);

        for (property in this._valuesEnd) {

            // Don't update properties that do not exist in the source object
            if (this._valuesStart[property] === undefined) {
                continue;
            }

            var start = this._valuesStart[property] || 0;
            var end = this._valuesEnd[property];

            if (end instanceof Array) {

                this._object[property] = this._interpolationFunction(end, value);

            } else {

                // Parses relative end values with start as base (e.g.: +10, -3)
                if (typeof (end) === "string") {

                    if (end.charAt(0) === "+" || end.charAt(0) === "-") {
                        end = start + parseFloat(end);
                    } else {
                        end = parseFloat(end);
                    }
                }

                // Protect against non numeric properties.
                if (typeof (end) === "number") {
                    this._object[property] = start + (end - start) * value;
                }

            }

        }

        if (this._onUpdateCallback !== null) {
            this._onUpdateCallback(this._object);
        }

        if (elapsed === 1) {

            if (this._repeat > 0) {

                if (isFinite(this._repeat)) {
                    this._repeat--;
                }

                // Reassign starting values, restart by making startTime = now
                for (property in this._valuesStartRepeat) {

                    if (typeof (this._valuesEnd[property]) === "string") {
                        this._valuesStartRepeat[property] = this._valuesStartRepeat[property] + parseFloat(this._valuesEnd[property]);
                    }

                    if (this._yoyo) {
                        var tmp = this._valuesStartRepeat[property];

                        this._valuesStartRepeat[property] = this._valuesEnd[property];
                        this._valuesEnd[property] = tmp;
                    }

                    this._valuesStart[property] = this._valuesStartRepeat[property];

                }

                if (this._yoyo) {
                    this._reversed = !this._reversed;
                }

                if (this._repeatDelayTime !== undefined) {
                    this._startTime = time + this._repeatDelayTime;
                } else {
                    this._startTime = time + this._delayTime;
                }

                return true;

            } else {

                if (this._onCompleteCallback !== null) {

                    this._onCompleteCallback(this._object);
                }

                for (var i = 0, numChainedTweens = this._chainedTweens.length; i < numChainedTweens; i++) {
                    // Make the chained tweens start exactly at the time they should,
                    // even if the `update()` method was called way past the duration of the tween
                    this._chainedTweens[i].start(this._startTime + this._duration);
                }

                return false;

            }

        }

        return true;

    }
};


/// ========================= TweenManager.js ============================

TWEEN.Easing = {

    Linear: {

        None: function (k) {

            return k;

        }

    },

    Quadratic: {

        In: function (k) {

            return k * k;

        },

        Out: function (k) {

            return k * (2 - k);

        },

        InOut: function (k) {

            if ((k *= 2) < 1) {
                return 0.5 * k * k;
            }

            return - 0.5 * (--k * (k - 2) - 1);

        }

    },

    Cubic: {

        In: function (k) {

            return k * k * k;

        },

        Out: function (k) {

            return --k * k * k + 1;

        },

        InOut: function (k) {

            if ((k *= 2) < 1) {
                return 0.5 * k * k * k;
            }

            return 0.5 * ((k -= 2) * k * k + 2);

        }

    },

    Quartic: {

        In: function (k) {

            return k * k * k * k;

        },

        Out: function (k) {

            return 1 - (--k * k * k * k);

        },

        InOut: function (k) {

            if ((k *= 2) < 1) {
                return 0.5 * k * k * k * k;
            }

            return - 0.5 * ((k -= 2) * k * k * k - 2);

        }

    },

    Quintic: {

        In: function (k) {

            return k * k * k * k * k;

        },

        Out: function (k) {

            return --k * k * k * k * k + 1;

        },

        InOut: function (k) {

            if ((k *= 2) < 1) {
                return 0.5 * k * k * k * k * k;
            }

            return 0.5 * ((k -= 2) * k * k * k * k + 2);

        }

    },

    Sinusoidal: {

        In: function (k) {

            return 1 - Math.cos(k * Math.PI / 2);

        },

        Out: function (k) {

            return Math.sin(k * Math.PI / 2);

        },

        InOut: function (k) {

            return 0.5 * (1 - Math.cos(Math.PI * k));

        }

    },

    Exponential: {

        In: function (k) {

            return k === 0 ? 0 : Math.pow(1024, k - 1);

        },

        Out: function (k) {

            return k === 1 ? 1 : 1 - Math.pow(2, - 10 * k);

        },

        InOut: function (k) {

            if (k === 0) {
                return 0;
            }

            if (k === 1) {
                return 1;
            }

            if ((k *= 2) < 1) {
                return 0.5 * Math.pow(1024, k - 1);
            }

            return 0.5 * (- Math.pow(2, - 10 * (k - 1)) + 2);

        }

    },

    Circular: {

        In: function (k) {

            return 1 - Math.sqrt(1 - k * k);

        },

        Out: function (k) {

            return Math.sqrt(1 - (--k * k));

        },

        InOut: function (k) {

            if ((k *= 2) < 1) {
                return - 0.5 * (Math.sqrt(1 - k * k) - 1);
            }

            return 0.5 * (Math.sqrt(1 - (k -= 2) * k) + 1);

        }

    },

    Elastic: {

        In: function (k) {

            if (k === 0) {
                return 0;
            }

            if (k === 1) {
                return 1;
            }

            return -Math.pow(2, 10 * (k - 1)) * Math.sin((k - 1.1) * 5 * Math.PI);

        },

        Out: function (k) {

            if (k === 0) {
                return 0;
            }

            if (k === 1) {
                return 1;
            }

            return Math.pow(2, -10 * k) * Math.sin((k - 0.1) * 5 * Math.PI) + 1;

        },

        InOut: function (k) {

            if (k === 0) {
                return 0;
            }

            if (k === 1) {
                return 1;
            }

            k *= 2;

            if (k < 1) {
                return -0.5 * Math.pow(2, 10 * (k - 1)) * Math.sin((k - 1.1) * 5 * Math.PI);
            }

            return 0.5 * Math.pow(2, -10 * (k - 1)) * Math.sin((k - 1.1) * 5 * Math.PI) + 1;

        }

    },

    Back: {

        In: function (k) {

            var s = 1.70158;

            return k * k * ((s + 1) * k - s);

        },

        Out: function (k) {

            var s = 1.70158;

            return --k * k * ((s + 1) * k + s) + 1;

        },

        InOut: function (k) {

            var s = 1.70158 * 1.525;

            if ((k *= 2) < 1) {
                return 0.5 * (k * k * ((s + 1) * k - s));
            }

            return 0.5 * ((k -= 2) * k * ((s + 1) * k + s) + 2);

        }

    },

    Bounce: {

        In: function (k) {

            return 1 - TWEEN.Easing.Bounce.Out(1 - k);

        },

        Out: function (k) {

            if (k < (1 / 2.75)) {
                return 7.5625 * k * k;
            } else if (k < (2 / 2.75)) {
                return 7.5625 * (k -= (1.5 / 2.75)) * k + 0.75;
            } else if (k < (2.5 / 2.75)) {
                return 7.5625 * (k -= (2.25 / 2.75)) * k + 0.9375;
            } else {
                return 7.5625 * (k -= (2.625 / 2.75)) * k + 0.984375;
            }

        },

        InOut: function (k) {

            if (k < 0.5) {
                return TWEEN.Easing.Bounce.In(k * 2) * 0.5;
            }

            return TWEEN.Easing.Bounce.Out(k * 2 - 1) * 0.5 + 0.5;

        }

    }

};

TWEEN.Interpolation = {

    Linear: function (v, k) {

        var m = v.length - 1;
        var f = m * k;
        var i = Math.floor(f);
        var fn = TWEEN.Interpolation.Utils.Linear;

        if (k < 0) {
            return fn(v[0], v[1], f);
        }

        if (k > 1) {
            return fn(v[m], v[m - 1], m - f);
        }

        return fn(v[i], v[i + 1 > m ? m : i + 1], f - i);

    },

    Bezier: function (v, k) {

        var b = 0;
        var n = v.length - 1;
        var pw = Math.pow;
        var bn = TWEEN.Interpolation.Utils.Bernstein;

        for (var i = 0; i <= n; i++) {
            b += pw(1 - k, n - i) * pw(k, i) * v[i] * bn(n, i);
        }

        return b;

    },

    CatmullRom: function (v, k) {

        var m = v.length - 1;
        var f = m * k;
        var i = Math.floor(f);
        var fn = TWEEN.Interpolation.Utils.CatmullRom;

        if (v[0] === v[m]) {

            if (k < 0) {
                i = Math.floor(f = m * (1 + k));
            }

            return fn(v[(i - 1 + m) % m], v[i], v[(i + 1) % m], v[(i + 2) % m], f - i);

        } else {

            if (k < 0) {
                return v[0] - (fn(v[0], v[0], v[1], v[1], -f) - v[0]);
            }

            if (k > 1) {
                return v[m] - (fn(v[m], v[m], v[m - 1], v[m - 1], f - m) - v[m]);
            }

            return fn(v[i ? i - 1 : 0], v[i], v[m < i + 1 ? m : i + 1], v[m < i + 2 ? m : i + 2], f - i);

        }

    },

    Utils: {

        Linear: function (p0, p1, t) {

            return (p1 - p0) * t + p0;

        },

        Bernstein: function (n, i) {

            var fc = TWEEN.Interpolation.Utils.Factorial;

            return fc(n) / fc(i) / fc(n - i);

        },

        Factorial: (function () {

            var a = [1];

            return function (n) {

                var s = 1;

                if (a[n]) {
                    return a[n];
                }

                for (var i = n; i > 1; i--) {
                    s *= i;
                }

                a[n] = s;
                return s;

            };

        })(),

        CatmullRom: function (p0, p1, p2, p3, t) {

            var v0 = (p2 - p0) * 0.5;
            var v1 = (p3 - p1) * 0.5;
            var t2 = t * t;
            var t3 = t * t2;

            return (2 * p1 - 2 * p2 + v0 + v1) * t3 + (- 3 * p1 + 3 * p2 - 2 * v0 - v1) * t2 + v0 * t + p1;

        }

    }

};

//Tween script
TWEEN.Tween.prototype._isPaused = false;
TWEEN.Tween.prototype._pauseTime = null;

TWEEN.Tween.prototype.resume = function (tweenName) {
    if (!this._isPaused) {
        debugPrint("Tween Manager: " + tweenName + " has not been paused. Did you mean to call startTween this Tween instead?");
        return;
    }

    this._isPaused = !this._isPaused;

    this._startTime += new Date().getTime() - this._pauseTime;

    TWEEN.add(this);
};

TWEEN.Tween.prototype.pause = function (tweenName) {
    if (this._isPaused) {
        debugPrint("Tween Manager: Warning, " + tweenName + ", has already been paused.");
        return;
    }

    this._isPaused = !this._isPaused;

    this._pauseTime = new Date().getTime();

    TWEEN.remove(this);
};

// On update, update the Tween engine
function onUpdateEvent() {
    TWEEN.update();
}

// Bind an update event
var updateEvent = script.createEvent("UpdateEvent");
updateEvent.bind(onUpdateEvent);

// Resume a tween that has been paused
function resumeTween(tweenObject, _tweenName) {
    var tweenScriptComponent = findTween(tweenObject, _tweenName);
    if (tweenScriptComponent) {
        var tweenName = tweenScriptComponent.tweenName;
        if (tweenScriptComponent.playAll && tweenScriptComponent.tweenType == "chain") {
            for (var i = 0; i < tweenScriptComponent.allTweens.length; i++) {
                tweenScriptComponent.allTweens[i].resume(tweenName);
            }
        } else if (tweenScriptComponent.tween) {
            if (Array.isArray(tweenScriptComponent.tween)) {
                for (var j = 0; j < tweenScriptComponent.tween.length; j++) {
                    tweenScriptComponent.tween[j].resume(tweenName);
                }
            } else {
                tweenScriptComponent.tween.resume(tweenName);
            }
        } else {
            debugPrint("Tween Manager: Warning, trying to resume " + tweenName + ", which hasn't been initialized", true);
        }
    } else {
        debugPrint("Tween Manager: Trying to resume " + tweenName + ", which does not exist. Ensure that the Tween Type has been initialized and started.", true);
    }
}

// Pause a tween that is currently playing
function pauseTween(tweenObject, _tweenName) {
    var tweenScriptComponent = findTween(tweenObject, _tweenName);
    if (tweenScriptComponent) {
        var tweenName = tweenScriptComponent.tweenName;
        if (tweenScriptComponent.tweenType == "chain" && tweenScriptComponent.playAll) {
            for (var i = 0; i < tweenScriptComponent.allTweens.length; i++) {
                tweenScriptComponent.allTweens[i].pause(tweenName);
            }
        } else if (tweenScriptComponent.tween) {
            if (Array.isArray(tweenScriptComponent.tween)) {
                for (var j = 0; j < tweenScriptComponent.tween.length; j++) {
                    tweenScriptComponent.tween[j].pause(tweenName);
                }
            } else {
                tweenScriptComponent.tween.pause(tweenName);
            }
        } else {
            debugPrint("Tween Manager: Warning, trying to pause " + tweenName + ", which hasn't been initialized", true);
        }
    } else {
        debugPrint("Tween Manager: Trying to pause " + tweenName + ", which does not exist. Ensure that the Tween Type has been initialized and started.", true);
    }
}

function isPaused(tweenObject, tweenName) {
    var tweenScriptComponent = findTween(tweenObject, tweenName);
    if (tweenScriptComponent) {
        if (tweenScriptComponent.tween) {
            if (Array.isArray(tweenScriptComponent.tween)) {
                return tweenScriptComponent.tween[tweenScriptComponent.tween.length - 1]._isPaused;
            }

            return tweenScriptComponent.tween._isPaused;
        }

        return false;
    }

    debugPrint("TweenManager: You are trying to check if " + tweenName + " is currently paused, but a Tween of that type does not exist on " + tweenObject.name + ".", true);
}

// Return true if a tween is playing, false otherwise
function isPlaying(tweenObject, tweenName) {
    var tweenScriptComponent = findTween(tweenObject, tweenName);
    if (tweenScriptComponent) {
        if (tweenScriptComponent.tween) {
            if (Array.isArray(tweenScriptComponent.tween)) {
                return tweenScriptComponent.tween[tweenScriptComponent.tween.length - 1]._isPlaying;
            }

            return tweenScriptComponent.tween._isPlaying;
        }

        return false;
    }

    debugPrint("TweenManager: You are trying to check if " + tweenName + " is currently playing, but a Tween of that type does not exist on " + tweenObject.name + ".", true);
}

// Global function to start a tween on a specific object
function startTween(tweenObject, tweenName, completeCallback, startCallback, stopCallback) {
    var tweenScriptComponent = findTween(tweenObject, tweenName);
    if (tweenScriptComponent) {
        debugPrint("Tween Manager: Starting " + tweenName);

        // Remove tween if it already exists
        if (tweenScriptComponent.tween) {
            if (Array.isArray(tweenScriptComponent.tween)) {
                for (var i in tweenScriptComponent.tween) {
                    TWEEN.remove(tweenScriptComponent.tween[i]);
                }
            } else {
                TWEEN.remove(tweenScriptComponent.tween);
            }
        }

        // Start the tween
        tweenScriptComponent.startTween();

        // Add the callbacks
        if (tweenScriptComponent.tweenType == "chain") {
            if (completeCallback) {
                if (tweenScriptComponent.playAll) {
                    tweenScriptComponent.longestTween.onComplete(completeCallback);
                } else {
                    if (Array.isArray(tweenScriptComponent.lastTween)) {
                        tweenScriptComponent.lastTween[tweenScriptComponent.lastTween.length - 1].onComplete(completeCallback);
                    } else {
                        tweenScriptComponent.lastTween.onComplete(completeCallback);
                    }
                }
            }

            if (startCallback) {
                if (Array.isArray(tweenScriptComponent.firstTween)) {
                    tweenScriptComponent.firstTween[tweenScriptComponent.firstTween.length - 1].onStart(startCallback);
                } else {
                    tweenScriptComponent.firstTween.onStart(startCallback);
                }
            }

            if (stopCallback) {
                for (var k = 0; k < tweenScriptComponent.allTweens.length; k++) {
                    var currentTween = tweenScriptComponent.allTweens[k];
                    if (Array.isArray(currentTween)) {
                        for (var j = 0; j < currentTween.length; j++) {
                            currentTween[j].onStop(stopCallback);
                        }
                    } else {
                        currentTween.onStop(stopCallback);
                    }
                }
            }
        } else {
            if (completeCallback) {
                if (Array.isArray(tweenScriptComponent.tween)) {
                    tweenScriptComponent.tween[tweenScriptComponent.tween.length - 1].onComplete(completeCallback);
                } else {
                    tweenScriptComponent.tween.onComplete(completeCallback);
                }
            }

            if (startCallback) {
                if (Array.isArray(tweenScriptComponent.tween)) {
                    tweenScriptComponent.tween[tweenScriptComponent.tween.length - 1].onStart(startCallback);
                } else {
                    tweenScriptComponent.tween.onStart(startCallback);
                }
            }

            if (stopCallback) {
                if (Array.isArray(tweenScriptComponent.tween)) {
                    tweenScriptComponent.tween[tweenScriptComponent.tween.length - 1].onStop(stopCallback);
                } else {
                    tweenScriptComponent.tween.onStop(stopCallback);
                }
            }
        }
    }
}

// Global function to stop a tween on a specific object
function stopTween(tweenObject, tweenName) {
    var tweenScriptComponent = findTween(tweenObject, tweenName);
    if (tweenScriptComponent) {
        debugPrint("Tween Manager: Stopping " + tweenName);
        if (tweenScriptComponent.tweenType == "chain") {
            if (tweenScriptComponent.playAll && tweenScriptComponent.allTweens) {
                for (var i = 0; i < tweenScriptComponent.allTweens.length; i++) {
                    tweenScriptComponent.allTweens[i].stop();
                }
                return;
            } else if (tweenScriptComponent.tween) {
                if (Array.isArray(tweenScriptComponent.tween)) {
                    for (var j = 0; j < tweenScriptComponent.tween.length; j++) {
                        tweenScriptComponent.tween[j].stop();
                    }
                } else {
                    tweenScriptComponent.tween.stop();
                }
            } else {
                debugPrint("Tween Manager: Warning, trying to stop " + tweenName + ", which hasn't been started");
            }

            return;
        }

        if (tweenScriptComponent.tween) {
            if (Array.isArray(tweenScriptComponent.tween)) {
                for (var k = 0; k < tweenScriptComponent.tween.length; k++) {
                    tweenScriptComponent.tween[k].stop();
                }
            } else {
                tweenScriptComponent.tween.stop();
            }
        } else {
            debugPrint("Tween Manager: Warning, trying to stop " + tweenName + ", which hasn't been started");
        }
    }
}

// Manually set the start value of a tween
function setStartValue(tweenObject, tweenName, startValue) {
    var tweenScriptComponent = findTween(tweenObject, tweenName);

    if (tweenScriptComponent) {
        if (tweenScriptComponent.setStart) {
            tweenScriptComponent.setStart(startValue);
        } else {
            debugPrint("Tween Manager: You cannot manually set the start value of " + tweenName);
        }
    }
}

// Manually set the end value of a tween
function setEndValue(tweenObject, tweenName, endValue) {
    var tweenScriptComponent = findTween(tweenObject, tweenName);

    if (tweenScriptComponent) {
        if (tweenScriptComponent.setEnd) {
            tweenScriptComponent.setEnd(endValue);
        } else {
            debugPrint("Tween Manager: You cannot manually set the end value of " + tweenName);
        }
    }
}

// Global function to reset and object to its starting values
function resetObject(tweenObject, tweenName) {
    var tweenScriptComponent = findTween(tweenObject, tweenName);
    if (tweenScriptComponent) {
        debugPrint("Tween Manager: Resetting Object " + tweenName);
        tweenScriptComponent.resetObject();
    }
}

// Global function to reset and start tween again
function resetTween(tweenObject, tweenName) {
    var tweenScriptComponent = findTween(tweenObject, tweenName);
    resetTweenComponent(tweenScriptComponent);
}

function resetTweenComponent(tweenScriptComponent) {
    if (tweenScriptComponent) {
        debugPrint("Tween Manager: Resetting tween " + tweenScriptComponent.tweenName);

        if (tweenScriptComponent.tweenType == "chain") {
            tweenScriptComponent.backwards = false;
            debugPrint("Tween Manager: Chain Tween reset is not fully supported");
        }

        if (tweenScriptComponent.movementType && tweenScriptComponent.movementType > 0) {
            debugPrint("Tween Manager: Reset for this tween movement type is not fully supported");
        }

        // Remove tween if it already exists
        if (tweenScriptComponent.tween) {
            if (Array.isArray(tweenScriptComponent.tween)) {
                for (var i in tweenScriptComponent.tween) {
                    TWEEN.remove(tweenScriptComponent.tween[i]);
                }
            } else {
                TWEEN.remove(tweenScriptComponent.tween);
            }
        }
        tweenScriptComponent.resetObject();
    }
}

// Global function to reset all tweens
function resetTweens() {
    for (var i = 0; i < script.registry.length; i++) {
        var tweenScriptComponent = script.registry[i];
        resetTweenComponent(tweenScriptComponent);
    }
}

// Global function to restart all playAutomatically tweens
function restartAutoTweens() {
    for (var i = 0; i < script.registry.length; i++) {
        var tweenScriptComponent = script.registry[i];

        if (tweenScriptComponent && tweenScriptComponent.playAutomatically) {
            debugPrint("Restarting tween " + tweenScriptComponent.tweenName);

            // Start the tween
            tweenScriptComponent.startTween();
        }
    }
}

script.registry = [];

function addToRegistry(tweenScriptComponent) {
    if (tweenScriptComponent) {
        debugPrint("Adding tween " + tweenScriptComponent.tweenName + " to Tween Manager registry");
        script.registry[script.registry.length++] = tweenScriptComponent;
        return true;
    }
    return false;
}

function cleanRegistry() {
    script.registry = [];
}

// Create the easing type string that will be used by the tween
function getTweenEasingType(easingFunction, easingType) {
    if (easingFunction == "Linear") {
        return TWEEN.Easing.Linear.None;
    }

    return TWEEN.Easing[easingFunction][easingType];
}

// Configures the loop type for the tween
function setTweenLoopType(tween, loopType) {
    switch (loopType) {
        case 0: // None
            break;
        case 1: // Loop
            tween.repeat(Infinity);
            break;
        case 2: // Ping Pong
            tween.yoyo(true);
            tween.repeat(Infinity);
            break;
        case 3: // Ping Pong Once
            tween.yoyo(true);
            tween.repeat(1);
            break;
    }
}

// Finds tween on an object by name
function findTween(tweenObject, tweenName) {
    var scriptComponents = tweenObject.getComponents("Component.ScriptComponent");

    for (var i = 0; i < scriptComponents.length; i++) {
        var scriptComponent = scriptComponents[i];
        if (scriptComponent) {
            if (scriptComponent.tweenName) {
                if (tweenName == scriptComponent.tweenName) {
                    return scriptComponent;
                }
            }
        } else {
            debugPrint("Tween Manager: Tween type hasn't initialized. Ensure that " + tweenName + " is on \"Lens Turn On\" and that Tween Manager is at the top of the Objects Panel.", true);
            return;
        }
    }

    debugPrint("Tween Manager: Tween, " + tweenName + ", is not found. Ensure that " + tweenName + " is on \"Lens Turn On\" and that Tween Manager is at the top of the Objects Panel.", true);
}

// Finds tween on an object and its children by name
function findTweenRecursive(tweenObject, tweenName) {
    var scriptComponents = tweenObject.getComponents("Component.ScriptComponent");
    for (var i = 0; i < scriptComponents.length; i++) {
        var scriptComponent = scriptComponents[i];
        if (scriptComponent) {
            if (scriptComponent.tweenName) {
                if (tweenName == scriptComponent.tweenName) {
                    return scriptComponent;
                }
            }
        } else {
            debugPrint("Tween Manager: Tween type hasn't initialized. Ensure that " + tweenName + " is on \"Lens Turn On\" and that Tween Manager is at the top of the Objects Panel.", true);
            return;
        }
    }

    for (var j = 0; j < tweenObject.getChildrenCount(); j++) {
        var result = findTweenRecursive(tweenObject.getChild(j), tweenName);
        if (result) {
            return result;
        }
    }
}

// Finds a generic tween on an object by name
function getGenericTweenValue(tweenObject, tweenName) {
    var scriptComponents = tweenObject.getComponents("Component.ScriptComponent");

    for (var i = 0; i < scriptComponents.length; i++) {
        var scriptComponent = scriptComponents[i];

        if (scriptComponent) {
            if (tweenName == scriptComponent.tweenName) {
                if (scriptComponent.tweenType == "value") {
                    if (scriptComponent.tween) {
                        if (!scriptComponent.tween._isPlaying) {
                            debugPrint("Tween Manager: Tween Value, " + tweenName + ", is not currently playing. Ensure that it has been started by either calling its startTween() function or by setting it to Play Automatically.", true);
                        }
                    } else {
                        debugPrint("Tween Manager: Tween Value, " + tweenName + ", has not been set up. Ensure that this Tween Value is ordered before every other script that uses it in the Objects Panel and Inspector. Try initializing it in the Initialized event and scripting in the Lens Turn On event.", true);
                    }

                    return scriptComponent.value;
                }
            }
        } else {
            debugPrint("Tween Manager: Tween Value, " + tweenName + ", hasn't initialized. Needs to initialize prior to scripting playback. Likely an order of operations issue. Try initializing tween type in the Initialized event and scripting it in the Lens Turn On event. Or, try moving the Tween Manager to the top of the Objects hierarchy.", true);
            return;
        }
    }

    debugPrint("Tween Manager: Tween Value, " + tweenName + ", is not found. Ensure that " + tweenName + " is enabled and the Tween Name passed into this function exactly matches the specified Tween Name for this Tween Value in the Inspector.", true);
}

// Returns the opposite easing type to the one passed in as a parameter; for use with ping pong
function getSwitchedEasingType(initialType) {
    switch (initialType) {
        case "In":
            return "Out";
        case "Out":
            return "In";
        default:
            return "InOut";
    }
}

function debugPrint(msg, force) {
    if (script.tweenPrintDebugLog || force) {
        print(msg);
    }
}