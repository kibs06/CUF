//@component
// ShoeVisualization.js
// Version: 1.0.0
// Event: On Awake
// Description: Sets added objects in visualization mode (rotation in the center of the screen)
// 
// public api:
// script.addObject(SceneObject)
// Adds a new scene object to the visualization collection
// 
// script.setActive(index)
// Activate model index for visualization

//@input bool advanced
//@input bool verticalRotation {"showIf": "advanced"}
//@input SceneObject parent {"showIf": "advanced"}
//@input SceneObject scaleProxy {"showIf": "advanced"}
//@input vec3 rotationOffset {"showIf": "advanced"}
//@input int renderOrder {"showIf": "advanced"}
//@input Component.InteractionComponent interactionComponent

// Check inputs
if (!script.parent) {
    print("error: parent SceneObject not set");
    script.enabled = false;
    return;
}

if (!script.scaleProxy) {
    print("error: scaleProxy SceneObject not set");
    script.enabled = false;
    return;
}

script.box = script.parent.getChild(0);
var objHelpers = require("./SceneObjectHelpersModule");
const SPIN_DELTA = new vec2(0.001,0);
const CUSTOM_OCCLUDER_NAME = "Custom Occluder";
const CC_LEFT_OCCLUDER_NAME = "Left Foot Occluder 2";

var touchPos = new vec2(0,0);
var touchDelta = SPIN_DELTA;
var lastTouchPos = new vec2(0,0);
var speed = 0.5;
var accum = quat.quatIdentity();
var touches = [];
var initialScale = 1/script.scaleProxy.getTransform().getWorldScale().x;
var models = [];
var shoeComponents = [];

var X_SENSITIVITY = -2;
var Y_SENSITIVITY = script.verticalRotation ? -2 : 0;

script.interactionComponent.onTouchStart.add(function(touchStartEventArgs) {
    lastTouchPos = touchStartEventArgs.position;
    touches.push(touchStartEventArgs.touchId);
});

script.interactionComponent.onTouchMove.add(function(touchStartEventArgs) {
    if (touchStartEventArgs.touchId != touches[0]) {
        return;
    }
    touchPos = touchStartEventArgs.position;
    touchDelta =  lastTouchPos.sub(touchPos).uniformScale(speed);
    lastTouchPos = touchPos;
});

script.interactionComponent.onTouchEnd.add(function(eventData) {
    touches = [];
    touchDelta = SPIN_DELTA;
});

script.createEvent("UpdateEvent").bind(function(eventData) {
    if (touches.length > 1) {
        var newScale = script.scaleProxy.getTransform().getWorldScale().uniformScale(initialScale);
        script.box.getTransform().setWorldScale(newScale);
        return;
    }

    var testQuat = quat.fromEulerAngles(Y_SENSITIVITY * touchDelta.y, X_SENSITIVITY * touchDelta.x,0);
    accum = accum.multiply(testQuat);
    accum = quat.slerp(accum, quat.quatIdentity(), 0.1);
    var objectRot = script.parent.getTransform().getWorldRotation();
    var newRot = objectRot.multiply(accum);
    script.parent.getTransform().setWorldRotation(newRot);
    var boxRot = script.box.getTransform().getWorldRotation();
    script.parent.getTransform().setWorldRotation(quat.quatIdentity());
    script.box.getTransform().setWorldRotation(boxRot);    
});

script.setActive = function(index) {
    models.forEach(function(o, i) {
        if (!isNull(o)) {
            o.enabled = i == index;
        } else if (i==index) {
            models[i].enabled = true;
        }
    });
};

function copyVisModel(shoe) {
    var newModel = script.box.copyWholeHierarchy(shoe);
    newModel.getTransform().setLocalPosition(script.rotationOffset);
    
    newModel.renderOrder = script.parent.renderOrder;    
    
    // Destroy the occluder that is added by the Foot Tracking CC
    var occluder = objHelpers.findChildObjectWithName(newModel, CC_LEFT_OCCLUDER_NAME);
    if (occluder) {
        occluder.destroy();
    }

    // Destroy custom occluder (if exists)
    occluder = objHelpers.findChildObjectWithName(newModel, CUSTOM_OCCLUDER_NAME);
    if (!isNull(occluder)) {
        occluder.destroy();
    }

    var visuals = objHelpers.getComponentsRecursive(newModel, "Component.Visual");
    visuals.forEach(function(o) {
        o.setRenderOrder(script.renderOrder);
    });

    newModel.enabled = false;

    return newModel;
}

script.addObject = function(sceneObject) {
    var shoeComp = sceneObject.getComponent("ScriptComponent");
    if (!shoeComp) {
        print("error in addObject: could not find a script attached to the provided object");
        return;
    }

    shoeComponents.push(shoeComp);
    models.push(null);

    // enable to fire init on the component if disabled on startup
    sceneObject.enabled = true;
    if (shoeComp.leftFoot) {
        models[models.length-1] = copyVisModel(shoeComp.leftFoot);
    }    
    sceneObject.enabled = false;
};