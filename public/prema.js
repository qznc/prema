(function(){
	var now = new Date();
	var msPerMinute = 60 * 1000;
	var msPerHour = 60 * msPerMinute;
	var msPerDay = msPerHour * 24;
	var msPerMonth = msPerDay * 30;
	var msPerYear = msPerDay * 365;
	function relDate(date) {
		var elapsed = now - date; // in milliseconds
		var prefix;
		if (elapsed > 0) {
			prefix = function(diff) { return diff+' ago'; }
		} else {
			prefix = function(diff) { return 'in '+diff; }
			elapsed = -elapsed;
		}
		if (elapsed < msPerMinute*2)
			return prefix(Math.round(elapsed/1000)+' sec');
		else if (elapsed < msPerHour*2)
			return prefix(Math.round(elapsed/msPerMinute)+' min');
		else if (elapsed < msPerDay*2)
			return prefix(Math.round(elapsed/msPerHour)+'h');
		else if (elapsed < msPerMonth*2)
			return prefix(Math.round(elapsed/msPerDay)+' days');
		else if (elapsed < msPerYear*2)
			return prefix(Math.round(elapsed/msPerMonth)+' months');
		else
			return prefix(Math.round(elapsed/msPerYear)+' years');
	}
	function showRelativeTimes() {
		var time_tags = document.getElementsByTagName("time");
		for (var i=0; i<time_tags.length; i++) {
			var tt = time_tags[i];
			var date = tt.getAttribute("datetime");
			tt.title = date;
			tt.innerHTML = relDate(new Date(date));
		}
	}
	showRelativeTimes();
})();
