return {
    riot=true;
    id = 'FlatEarthTristana';
    name = 'FlatEarth Tristana';
    type = "Champion";
    load = function()
     	return player.charName == "Tristana"
    end;
}