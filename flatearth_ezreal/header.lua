return {
    riot=true;
    id = 'FlatEarthEzreal';
    name = 'FlatEarth Ezreal';
    type = "Champion";
    load = function()
     	return player.charName == "Ezreal"
    end;
}