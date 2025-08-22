# NOTE: only doing this in development as some production environments (Heroku)
# NOTE: are sensitive to local FS writes, and besides -- it's just not proper
# NOTE: to have a dev-mode tool do its thing in production.
if Rails.env.development?
  # Hook into Rails migration tasks to automatically annotate models
  namespace :db do
    task :annotate do
      puts "Annotating models..."
      system("bundle exec annotaterb models --show-foreign-keys --show-indexes --classified-sort")
    end
  end

  # Run annotation after migrations
  Rake::Task["db:migrate"].enhance do
    Rake::Task["db:annotate"].invoke
  end

  # Run annotation after rollbacks
  Rake::Task["db:rollback"].enhance do
    Rake::Task["db:annotate"].invoke
  end

  # Run annotation after database resets
  if Rake::Task.task_defined?("db:reset")
    Rake::Task["db:reset"].enhance do
      Rake::Task["db:annotate"].invoke
    end
  end

  # Run annotation after database setup
  if Rake::Task.task_defined?("db:setup")
    Rake::Task["db:setup"].enhance do
      Rake::Task["db:annotate"].invoke
    end
  end
end
