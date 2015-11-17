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
	var b = 100.0; // NOTE must match source/model.d
	function LMSR_C(yes, no) {
		return b * Math.log(Math.exp(yes/b) + Math.exp(no/b));
	}
	function LMSR_cost(yes, no, amount) {
		return LMSR_C(yes+amount, no) - LMSR_C(yes, no);
	}
	function LMSR_chance(yes, no) {
		var y =  LMSR_cost(yes, no, 1);
		var n =  LMSR_cost(no, yes, 1);
		return y / (y+n);
	}
	function roundDigits(value,digits) {
		var factor = Math.pow(10.0,digits);
		return Math.round(value*factor)/factor;
	}
	function costUpdates() {
		var share_amount = document.getElementById("share_amount");
		if (!share_amount) return; // cannot buy shares on this page
		var type = document.getElementById("share_type");
		var yes = parseInt(document.getElementById("yes_shares").innerHTML);
		var no = parseInt(document.getElementById("no_shares").innerHTML);
		function doUpdate() {
			var amount = parseInt(share_amount.value);
			var price = document.getElementById("price");
			var future_chance = document.getElementById("future_chance");
			if (share_type.value == "yes") {
				price.innerHTML = roundDigits(LMSR_cost(yes,no,amount),2)+"¢";
				future_chance.innerHTML = Math.round(LMSR_chance(yes+amount,no)*100)+"%";
			} else {
				price.innerHTML = roundDigits(LMSR_cost(no,yes,amount),2)+"¢";
				future_chance.innerHTML = Math.round(LMSR_chance(yes,no+amount)*100)+"%";
			}
		}
		share_amount.onkeyup = doUpdate;
		share_amount.onchange = doUpdate;
		type.onchange = doUpdate;
		doUpdate(); // once initially
	}
	showRelativeTimes();
	costUpdates();
})();
