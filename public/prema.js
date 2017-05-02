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
	function LMSR_C(b, yes, no) {
		return b * Math.log(Math.exp(yes/b) + Math.exp(no/b));
	}
	function LMSR_cost(b, yes, no, amount) {
		return LMSR_C(b, yes+amount, no) - LMSR_C(b, yes, no);
	}
	function LMSR_chance(b, yes, no) {
		var y =  LMSR_cost(b, yes, no, 1);
		var n =  LMSR_cost(b, no, yes, 1);
		return y / (y+n);
	}
	function roundDigits(value,digits) {
		var factor = Math.pow(10.0,digits);
		return Math.round(value*factor)/factor;
	}
	function costUpdates() {
		var share_amount = document.getElementById("share_amount");
		if (!share_amount) return; // cannot buy shares on this page
		var cash = parseInt(document.getElementById("cash").innerHTML);
		var type = document.getElementById("share_type");
		var yes = parseInt(document.getElementById("yes_shares").innerHTML);
		var no = parseInt(document.getElementById("no_shares").innerHTML);
		var b = parseInt(document.getElementById("b").innerHTML);
		function doUpdate() {
			var amount = parseInt(share_amount.value);
			var price = document.getElementById("price");
			var future_chance = document.getElementById("future_chance");
			var cost;
			if (share_type.value == "yes") {
				cost = LMSR_cost(b,yes,no,amount);
				future_chance.innerHTML = Math.round(LMSR_chance(b,yes+amount,no)*100)+"%";
			} else {
				cost = LMSR_cost(b,no,yes,amount);
				future_chance.innerHTML = Math.round(LMSR_chance(b,yes,no+amount)*100)+"%";
			}
			if (cost > cash) {
				price.innerHTML = "too much";
				price.className = "too_much";
			} else {
				var tax = Math.abs(cost*0.01);
				price.innerHTML = roundDigits(cost,3)+"¢ (+"+roundDigits(tax,3)+"¢ tax)";
				price.className = "";
			}
		}
		share_amount.onkeyup = doUpdate;
		share_amount.onchange = doUpdate;
		type.onchange = doUpdate;
		doUpdate(); // once initially
	}
	function createCostUpdates() {
		var b = document.getElementById("b");
		if (!b) return; // cannot create predictions on this page
		var max_loss = document.getElementById("max_loss");
		var b_txt = document.getElementById("b_txt");
		if (!b_txt) return; // cannot change b on this page
		function doUpdate() {
			var amount = parseInt(b.value);
			b_txt.innerHTML = b.value;
			var price = amount * Math.log(2);
			max_loss.innerHTML = roundDigits(price,3)+"¢";
		}
		b.onkeyup = doUpdate;
		b.onmouseup = doUpdate;
		b.onchange = doUpdate;
		doUpdate(); // once initially
	}
	showRelativeTimes();
	costUpdates();
	createCostUpdates();
})();
