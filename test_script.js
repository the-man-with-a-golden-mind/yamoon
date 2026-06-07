const fs = require('fs');
const yaml = require('js-yaml');
const parsed = yaml.load(fs.readFileSync('examples/advanced_yamagotchi.hyml', 'utf8'));
console.log("YAML parsed successfully.");
