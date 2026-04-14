class ValidationError extends Error {
    constructor(msg) {
        super(msg);
    }
}

function validate(input) {
    if (!input) {
        throw new ValidationError("missing input");
    }
    return input;
}

function process(data) {
    try {
        return validate(data);
    } catch (e) {
        throw new Error("processing failed");
    }
}
