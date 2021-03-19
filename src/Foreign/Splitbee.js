const splitbee = require('@splitbee/web').default;

exports.init = () => {
  try {
    splitbee.init()
  } catch (e) { }
}

exports.track = eventName => () => {
  try {
    splitbee
      .track(eventName)
      .catch(() => {})
  } catch (e) { }
}

exports.trackWithData = (eventName) => (data) => () => {
  try {
    splitbee
      .track(eventName, data)
      .catch(() => {})
  } catch (e) { }
}

exports.userSet = (data) => () => {
  try {
    splitbee
      .user.set(data)
      .catch(() => {})
  } catch (e) { }
}
