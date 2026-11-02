//@component
// Shoe Controller.js
// Version: 1.0.0
// Event: On Awake
// Description: Handles switching between visualization and try-on, managing hints, and switching shoe models

//@input SceneObject[] shoeSceneObjects
//@input SceneObject footHint
//@input bool enableVisualization = true
//@input SceneObject visualizationRoot {"showIf": "enableVisualization"}
//@input SceneObject cameraHint {"showIf": "enableVisualization"}

var isTryOn = true;
var updateEvent = script.createEvent("UpdateEvent");
var hintShown = false;
var lastIndex = 0;
var visualizationScript;

var activeTracker = null;

updateEvent.bind(function() {
    if (!isNull(activeTracker) && activeTracker.isTracking()) {        
        if (script.footHint != null) {
            script.footHint.enabled = false;
        }
        hintShown = true;
        updateEvent.enabled = false;
    }
});
updateEvent.enabled = false;

script.setShoe = function(index) {    
    if (!script.shoeSceneObjects || index < 0 || index >= script.shoeSceneObjects.length) {
        return;
    }
    script.shoeSceneObjects.forEach(function(so) {
        so.enabled = false;
    });
    
    script.shoeSceneObjects[index].enabled = isTryOn;
    activeTracker = script.shoeSceneObjects[index].getComponent("Component.ScriptComponent");
            
    if (script.enableVisualization) {
        script.visualizationRoot.enabled = !isTryOn;
        visualizationScript.setActive(index);
    }

    lastIndex = index;
};

function setHint() {
    if (isTryOn) {
        if (!hintShown) {
            updateEvent.enabled = true;
            if (script.footHint != null) {
                script.footHint.enabled = true;
            }
        }
    } else {
        updateEvent.enabled = false;
        if (script.footHint != null) {
            script.footHint.enabled = false;
        }
    }
    
}

script.createEvent("CameraFrontEvent").bind(function() {
    isTryOn = !script.enableVisualization;
    script.setShoe(lastIndex);
        
    setHint();
});

script.createEvent("CameraBackEvent").bind(function() {
    isTryOn = true;    
    script.setShoe(lastIndex);
    
    setHint();
});

function initialize() {
    if (script.hint != null) {
        script.hint.enabled = false;
    }

    if (script.enableVisualization && script.visualizationRoot) {
        visualizationScript = script.visualizationRoot.getComponent("Component.ScriptComponent");

        if (!script.shoeSceneObjects) {
            return;
        }
        script.shoeSceneObjects.forEach(function(o) {
            visualizationScript.addObject(o);
        });        
    } else if (script.visualizationRoot) {
        script.visualizationRoot.enabled = false;

        script.cameraHint.enabled = false;
    }
}

initialize();