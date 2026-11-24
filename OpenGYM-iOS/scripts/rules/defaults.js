// 默认值只参与计算。输入里没有、算完仍等于默认值的字段不写回资料：否则新设备会把默认值
// 当成一次新修改存下来，iCloud 合并时盖掉其他设备上真实的设置。
export const withoutDefaults = (result, input, defaults) => {
  for (const [key, value] of Object.entries(defaults)) {
    if (!(key in input) && JSON.stringify(result[key]) === JSON.stringify(value)) delete result[key];
  }
  return result;
};
