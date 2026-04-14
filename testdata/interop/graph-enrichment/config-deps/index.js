const _ = require('lodash');
const express = require('express');

function processData(items) {
    return _.map(items, function(item) {
        return item.name;
    });
}

function startServer() {
    const app = express();
    app.listen(3000);
}

module.exports = { processData, startServer };
