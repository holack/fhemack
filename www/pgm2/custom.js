function needPlotRefresh() {
	var search = location.search;
	var room;
	if (search.indexOf('room=') > -1) {
		room = search.split('room=')[1].split('&')[0];
	}
	return room == 'Plots';
}

function refreshPlots() {
	$.get().done(function(data) {
		var response = $(data);
		$('embed').replaceWith($(response).find('embed'));
	});
}

$(document).ready(function() {
	if (needPlotRefresh()) {
		if (typeof(customConfig) !== 'undefined' && typeof(customConfig.plotRefresh) !== 'undefined') {
			window.setInterval('refreshPlots()', customConfig.plotRefresh * 1000);
		} else {
			window.setInterval('refreshPlots()', 5000);
		}
	}	
});
