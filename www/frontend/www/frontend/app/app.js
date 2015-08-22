/**
 * Setup the application
 */

Ext.Loader.setConfig({
    enabled: true,
    disableCaching: false,
    paths: {
        'FHEM': 'app'
    }
});

Ext.application({
    name: 'FHEM Frontend',
    requires: [
        'FHEM.view.Viewport'        
    ],

    controllers: [
        'FHEM.controller.MainController',
        'FHEM.controller.ChartController'
    ],

    launch: function() {
        
        // Gather information from FHEM to display status, devices, etc.
        var me = this,
            url = '../../../fhem?cmd=jsonlist&XHR=1';
        
        Ext.Ajax.request({
            method: 'GET',
            async: false,
            disableCaching: false,
            url: url,
            success: function(response){
                Ext.getBody().unmask();
                FHEM.info = Ext.decode(response.responseText);
                
                FHEM.version = FHEM.info.Results[0].devices[0].ATTR.version;
                
                Ext.each(FHEM.info.Results, function(result) {
                    //TODO: get more specific here...
                    if (result.list === "DbLog" && result.devices[0].NAME) {
                        FHEM.dblogname = result.devices[0].NAME;
                    }
                });
                if (!FHEM.dblogname && Ext.isEmpty(FHEM.dblogname) && FHEM.dblogname != "undefined") {
                    Ext.Msg.alert("Error", "Could not find a DbLog Configuration. Do you have DbLog already running?");
                } else {
                    Ext.create("FHEM.view.Viewport", {
                        hidden: true
                    });
                    
                    //removing the loadingimage
                    var p = Ext.DomQuery.select('p[class=loader]')[0],
                        img = Ext.DomQuery.select('#loading-overlay')[0];
                    p.removeChild(img);
                    // further configuration of viewport starts in maincontroller
                }
            },
            failure: function() {
                Ext.Msg.alert("Error", "The connection to FHEM could not be established");
            }
        });
        
    }
});