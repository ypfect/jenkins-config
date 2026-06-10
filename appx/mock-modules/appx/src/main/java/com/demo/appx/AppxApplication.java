package com.demo.appx;

import com.sun.net.httpserver.HttpServer;

import java.io.BufferedReader;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;

/**
 * appx 聚合 jar 启动入口。
 * 读取聚合后的 META-INF/appx-modules.list（由 build.sh 合并各模块碎片生成），
 * 反射加载每个模块，并启动一个最小 HTTP 服务（对标公司 appx 的 8800 web 服务）。
 */
public class AppxApplication {

  public static void main(String[] args) throws Exception {
    List<String> modules = loadModules();
    System.out.println("==> appx 聚合 jar 启动，加载模块: " + modules);

    int port = 8800;
    HttpServer server = HttpServer.create(new InetSocketAddress(port), 0);
    server.createContext("/", exchange -> {
      String body = "appx aggregated jar running\nmodules: " + modules + "\n";
      byte[] b = body.getBytes(StandardCharsets.UTF_8);
      exchange.sendResponseHeaders(200, b.length);
      try (OutputStream os = exchange.getResponseBody()) {
        os.write(b);
      }
    });
    server.start();
    System.out.println("==> HTTP 服务监听 :" + port);
  }

  private static List<String> loadModules() {
    List<String> result = new ArrayList<>();
    try (InputStream in = AppxApplication.class.getResourceAsStream("/META-INF/appx-modules.list")) {
      if (in == null) {
        System.out.println("WARN: 未找到 appx-modules.list");
        return result;
      }
      BufferedReader r = new BufferedReader(new InputStreamReader(in, StandardCharsets.UTF_8));
      String line;
      while ((line = r.readLine()) != null) {
        line = line.trim();
        if (line.isEmpty()) {
          continue;
        }
        Module m = (Module) Class.forName(line).getDeclaredConstructor().newInstance();
        result.add(m.name());
      }
    } catch (Exception ex) {
      ex.printStackTrace();
    }
    return result;
  }
}
